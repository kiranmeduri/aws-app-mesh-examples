#!/usr/bin/env bash

set -e

if [ -z $AWS_ACCOUNT_ID ]; then
    echo "AWS_ACCOUNT_ID environment variable is not set."
    exit 1
fi

if [ -z $AWS_DEFAULT_REGION ]; then
    echo "AWS_DEFAULT_REGION environment variable is not set."
    exit 1
fi

if [ -z $ENVOY_IMAGE ]; then
    echo "ENVOY_IMAGE environment variable is not set to App Mesh Envoy, see https://docs.aws.amazon.com/app-mesh/latest/userguide/envoy.html"
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
OUT_DIR="${DIR}/_output"
mkdir -p ${OUT_DIR}
PROJECT_NAME="$(basename ${DIR})"
ECR_IMAGE_PREFIX=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${PROJECT_NAME}
AWS_FLUENT_BIT_IMAGE="906394416424.dkr.ecr.us-west-2.amazonaws.com/aws-for-fluent-bit:latest"

deploy_images() {
    for app in curler colorapp feapp; do
        aws ecr describe-repositories --repository-name $PROJECT_NAME/$app >/dev/null 2>&1 || aws ecr create-repository --repository-name $PROJECT_NAME/$app
        docker build -t ${ECR_IMAGE_PREFIX}/${app} ${DIR}/${app}
        $(aws ecr get-login --no-include-email)
        docker push ${ECR_IMAGE_PREFIX}/${app}
    done
}

deploy_infra() {
    stack_name="${PROJECT_NAME}-infra"
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name $stack_name \
        --template-file "${DIR}/infra.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}"
}

lookup_cfn_output() {
    stack_name=$1
    key=$2
    output_val=$(aws cloudformation describe-stacks \
        --stack-name="${stack_name}" \
        --query="Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue" \
        --output=text)
}

lookup_cfn_export() {
    key=$1
    export_val=$(aws cloudformation list-exports \
        --query "Exports[?Name=='${key}'].Value" \
        --output=text)
}

deploy_app() {
    CONTAINER_PORT=8080
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-pre-app" \
        --template-file "${DIR}/pre-app.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}" "ContainerPort=${CONTAINER_PORT}"

    if [ -z $SKIP_TASK_DEFS ]; then
        lookup_cfn_export "${PROJECT_NAME}:TaskIamRole"
        TASK_IAM_ROLE=$export_val
        lookup_cfn_export "${PROJECT_NAME}:TaskExecutionIamRole"
        TASK_EXECUTION_IAM_ROLE=$export_val
        lookup_cfn_export "${PROJECT_NAME}:LogGroup"
        LOG_GROUP=$export_val
        lookup_cfn_export "${PROJECT_NAME}:ColorVirtualNodeName"
        COLOR_VIRTUAL_NODE_NAME=$export_val
        lookup_cfn_export "${PROJECT_NAME}:FrontVirtualNodeName"
        FRONT_VIRTUAL_NODE_NAME=$export_val
        lookup_cfn_export "${PROJECT_NAME}:DnsNamespaceName"
        dnsNamespaceName=$export_val
        lookup_cfn_export "${PROJECT_NAME}:ColorServiceRegistryName"
        COLOR_VIRTUAL_SERVICE_NAME="${export_val}.${dnsNamespaceName}"
        COLOR="green"
        COLOR_APP_IMAGE="${ECR_IMAGE_PREFIX}/colorapp"
        FRONT_APP_IMAGE="${ECR_IMAGE_PREFIX}/feapp"
        CURLER_APP_IMAGE="${ECR_IMAGE_PREFIX}/curler"
        MESH_NAME=$PROJECT_NAME

        eval "cat <<EOF
$(<${DIR}/taskdefs/colorapp.json)
EOF
" >${OUT_DIR}/colorapp.json

        color_task_def_arn=$(aws ecs register-task-definition \
            --family "${PROJECT_NAME}-colorapp" \
            --cli-input-json "file://${OUT_DIR}/colorapp.json" |
            jq -r ".taskDefinition.taskDefinitionArn")

        echo "Created task-definition for color app : ${color_task_def_arn}"

        eval "cat <<EOF
$(<${DIR}/taskdefs/feapp.json)
EOF
" >${OUT_DIR}/feapp.json

        front_task_def_arn=$(aws ecs register-task-definition \
            --family "${PROJECT_NAME}-feapp" \
            --cli-input-json "file://${OUT_DIR}/feapp.json" |
            jq -r ".taskDefinition.taskDefinitionArn")

        echo "Created task-definition for front app : ${front_task_def_arn}"
    else
        color_task_def_arn=$(aws ecs describe-task-definition \
            --task-definition "${PROJECT_NAME}-colorapp" |
            jq -r ".taskDefinition.taskDefinitionArn")

        echo "Using task-definition for color app : ${color_task_def_arn}"

        front_task_def_arn=$(aws ecs describe-task-definition \
            --task-definition "${PROJECT_NAME}-feapp" |
            jq -r ".taskDefinition.taskDefinitionArn")

        echo "Using task-definition for front app : ${front_task_def_arn}"
    fi

    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-app" \
        --template-file "${DIR}/app.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}" "ContainerPort=${CONTAINER_PORT}" "FrontTaskDef=${front_task_def_arn}" "ColorTaskDef=${color_task_def_arn}"
}

delete_cfn_stack() {
    stack_name=$1
    aws cloudformation delete-stack --stack-name $stack_name
    echo 'Waiting for the stack to be deleted, this may take a few minutes...'
    aws cloudformation wait stack-delete-complete --stack-name $stack_name
    echo 'Done'
}

confirm_service_linked_role() {
    aws iam get-role --role-name AWSServiceRoleForAppMesh >/dev/null
    [[ $? -eq 0 ]] ||
        (echo "Error: no service linked role for App Mesh" && exit 1)
}

print_endpoint() {
    echo "Public endpoint:"
    lookup_cfn_export "${PROJECT_NAME}:FrontEndpoint"
    echo "${export_val}/color"
}

deploy_stacks() {

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    echo "deploy infra..."
    deploy_infra

    echo "deploy app..."
    deploy_app

    confirm_service_linked_role
    print_endpoint
}

delete_stacks() {
    echo "delete app..."
    delete_cfn_stack "${PROJECT_NAME}-app"

    echo "delete infra..."
    delete_cfn_stack "${PROJECT_NAME}-infra"
}

action=${1:-"deploy"}
if [ "$action" == "delete" ]; then
    delete_stacks
    exit 0
fi

deploy_stacks
