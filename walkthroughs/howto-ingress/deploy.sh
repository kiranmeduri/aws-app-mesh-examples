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
PROJECT_NAME="$(basename ${DIR})"
STACK_NAME="appmesh-${PROJECT_NAME}"
ECR_IMAGE_PREFIX=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${PROJECT_NAME}
APPMESH_ENVOY_GATEWAY_IMAGE="${ECR_IMAGE_PREFIX}/aws-appmesh-envoy-gateway:$(git log -1 --format=%h src/aws-appmesh-envoy-gateway)"
CW_AGENT_IMAGE="${ECR_IMAGE_PREFIX}/cwagent:$(git log -1 --format=%h src/cwagent)"
BACKEND_APP_IMAGE="${ECR_IMAGE_PREFIX}/backend:$(git log -1 --format=%h src/backend)"

create_ecr_repository() {
    repository_name=$1
    aws ecr describe-repositories --repository-name ${repository_name} >/dev/null 2>&1 || aws ecr create-repository --repository-name ${repository_name}
}

deploy_images() {
    create_ecr_repository ${PROJECT_NAME}/aws-appmesh-envoy-gateway
    create_ecr_repository $PROJECT_NAME/backend

    # custom envoy image to bootstrap with gateway config
    $(aws ecr get-login --no-include-email --registry-ids 111345817488)
    docker build -t ${APPMESH_ENVOY_GATEWAY_IMAGE} ${DIR}/src/aws-appmesh-envoy-gateway

    $(aws ecr get-login --no-include-email)
    docker push ${APPMESH_ENVOY_GATEWAY_IMAGE}
    docker build -t ${BACKEND_APP_IMAGE} ${DIR}/src/backend
    docker push ${BACKEND_APP_IMAGE}
}

deploy() {
    stage=$1

    echo "Deploying stack ${STACK_NAME}, this may take a few minutes..."
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name ${STACK_NAME} \
        --template-file "$DIR/deploy/$stage.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "EnvoyImage=${APPMESH_ENVOY_GATEWAY_IMAGE}" \
        "CloudWatchAgentImage=${CW_AGENT_IMAGE}" \
        "BackendAppImage=${BACKEND_APP_IMAGE}"
}

delete_cfn_stack() {
    stack_name=$1
    aws cloudformation delete-stack --stack-name $stack_name
    echo "Waiting for the stack $stack_name to be deleted, this may take a few minutes..."
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
    prefix=$(aws cloudformation describe-stacks \
        --stack-name="${STACK_NAME}" \
        --query="Stacks[0].Outputs[?OutputKey=='FrontEndpoint'].OutputValue" \
        --output=text)
    echo "${prefix}/backend"
}

deploy_stacks() {
    confirm_service_linked_role

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    echo "deploy app using stage ${stage}"
    deploy "${stage}"

    print_endpoint
}

delete_stacks() {
    echo "delete stack ${STACK_NAME}..."
    delete_cfn_stack ${STACK_NAME}
}

action=${1:-"deploy"}
stage=${2:-"cfn-template"}
if [ "$action" == "delete" ]; then
    delete_stacks
    exit 0
fi

deploy_stacks
