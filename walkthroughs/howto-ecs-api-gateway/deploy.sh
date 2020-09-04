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

AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
PROJECT_NAME="$(basename ${DIR})"
STACK_NAME="appmesh-${PROJECT_NAME}"

ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
ECR_IMAGE_PREFIX=${ECR_URL}/${PROJECT_NAME}
COLOR_APP_IMAGE="${ECR_IMAGE_PREFIX}/colorapp:$(git log -1 --format=%h src/colorapp)"
CAT_APP_IMAGE="${ECR_IMAGE_PREFIX}/catapp:$(git log -1 --format=%h src/catapp)"
CW_AGENT_IMAGE="${ECR_IMAGE_PREFIX}/cwagent:$(git log -1 --format=%h src/cwagent)"
GOPROXY=${GOPROXY:-"https://proxy.golang.org"}

ecr_login() {
    if [ $AWS_CLI_VERSION -gt 1 ]; then
        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
            docker login --username AWS --password-stdin ${ECR_URL}
    else
        $(aws ecr get-login --no-include-email)
    fi
}

# deploy_images builds and pushes docker images for colorapp and feapp to ECR
deploy_images() {
    for f in cwagent colorapp catapp; do
        aws ecr describe-repositories --repository-name ${PROJECT_NAME}/${f} >/dev/null 2>&1 || aws ecr create-repository --repository-name ${PROJECT_NAME}/${f} >/dev/null
    done

    ecr_login
    docker build -t ${CW_AGENT_IMAGE} ${DIR}/src/cwagent && docker push ${CW_AGENT_IMAGE}
    docker build -t ${COLOR_APP_IMAGE} --build-arg GOPROXY=${GOPROXY} ${DIR}/src/colorapp && docker push ${COLOR_APP_IMAGE}
    docker build -t ${CAT_APP_IMAGE} --build-arg GOPROXY=${GOPROXY} ${DIR}/src/catapp && docker push ${CAT_APP_IMAGE}
}

deploy() {
    echo "Deploying stack ${STACK_NAME}, this may take a few minutes..."
    aws cloudformation deploy \
        --no-fail-on-empty-changeset \
        --stack-name ${STACK_NAME} \
        --template-file "$DIR/deploy.yaml" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "EnvoyImage=${ENVOY_IMAGE}" \
        "ColorAppImage=${COLOR_APP_IMAGE}" \
        "CatAppImage=${CAT_APP_IMAGE}" \
        "CloudWatchAgentImage=${CW_AGENT_IMAGE}"
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
    echo "${prefix}/color"
}

deploy_stacks() {
    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    confirm_service_linked_role
    deploy
    print_endpoint
}

delete_stacks() {
    echo "delete stack ${STACK_NAME}..."
    delete_cfn_stack ${STACK_NAME}
}

action=${1:-"deploy"}
if [ "$action" == "delete" ]; then
    delete_stacks
    exit 0
fi

deploy_stacks
