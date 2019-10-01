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
ECR_IMAGE_PREFIX=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${PROJECT_NAME}

deploy_images() {
    for f in colorapp feapp; do
        aws ecr describe-repositories --repository-name ${PROJECT_NAME}/${f} >/dev/null 2>&1 || aws ecr create-repository --repository-name ${PROJECT_NAME}/${f}
        docker build -t ${ECR_IMAGE_PREFIX}/${f} ${DIR}/${f}
        $(aws ecr get-login --no-include-email)
        docker push ${ECR_IMAGE_PREFIX}/${f}
    done
}

deploy_infra() {
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-infra" \
        --template-file "${DIR}/infra.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}"

    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-vpc-1" \
        --template-file "${DIR}/vpc-1.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}"

    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-vpc-2" \
        --template-file "${DIR}/vpc-2.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "ProjectName=${PROJECT_NAME}"
}

deploy_app() {
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-colorapp" \
        --template-file "${DIR}/colorapp.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "EnvoyImage=${ENVOY_IMAGE}" \
        "ColorAppImage=${ECR_IMAGE_PREFIX}/colorapp"

    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name "${PROJECT_NAME}-feapp" \
        --template-file "${DIR}/feapp.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "EnvoyImage=${ENVOY_IMAGE}" \
        "FrontAppImage=${ECR_IMAGE_PREFIX}/feapp"
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
    prefix=$(aws cloudformation describe-stacks \
        --stack-name="${PROJECT_NAME}-feapp" \
        --query="Stacks[0].Outputs[?OutputKey=='FrontEndpoint'].OutputValue" \
        --output=text)
    echo "${prefix}/color"
}

deploy_stacks() {
    confirm_service_linked_role

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    echo "deploy infra..."
    deploy_infra

    echo "deploy app..."
    deploy_app

    #print_endpoint
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
