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
PROJECT_NAME=$(basename ${DIR})
DNS_NAMESPACE_NAME="${PROJECT_NAME}.local"
MESH_NAME=${PROJECT_NAME}
ECR_IMAGE_PREFIX=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${PROJECT_NAME}

deploy_images() {
  for app in colorapp feapp; do
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
    --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "InputDnsNamespaceName=${DNS_NAMESPACE_NAME}"

  aws appmesh-preview describe-mesh --mesh-name ${MESH_NAME} >/dev/null 2>&1 ||
    aws appmesh-preview create-mesh --mesh-name ${MESH_NAME}
}

deploy_front_vnode() {
  cat <<EOF >${OUT_DIR}/front-node.json
{
  "spec": {
    "serviceDiscovery": {
      "awsCloudMap": {
        "namespaceName": "${DNS_NAMESPACE_NAME}",
        "serviceName": "front"
      }
    },
    "listeners": [
      {
        "portMapping": {
          "protocol": "http",
          "port": 8080
        }
      }
    ],
    "backends": [
      {
        "virtualService": {
          "virtualServiceName": "${color_service_name}"
        }
      }
    ]
  }
}
EOF

  aws appmesh-preview describe-virtual-node \
    --mesh-name ${MESH_NAME} \
    --virtual-node-name front-node >/dev/null 2>&1 ||
    aws appmesh-preview create-virtual-node \
      --mesh-name ${MESH_NAME} \
      --virtual-node-name front-node \
      --cli-input-json file://${OUT_DIR}/front-node.json
}

deploy_color_vnode() {
  cat <<EOF >${OUT_DIR}/color-node.json
{
  "spec": {
    "serviceDiscovery": {
      "awsCloudMap": {
        "serviceName": "color",
        "namespaceName": "${DNS_NAMESPACE_NAME}"
      }
    },
    "listeners": [
      {
        "portMapping": {
          "protocol": "http",
          "port": 8080
        }
      }
    ]
  }
}
EOF

  aws appmesh-preview describe-virtual-node \
    --mesh-name ${MESH_NAME} \
    --virtual-node-name color-node >/dev/null 2>&1 ||
    aws appmesh-preview create-virtual-node \
      --mesh-name ${MESH_NAME} \
      --virtual-node-name color-node \
      --cli-input-json file://${OUT_DIR}/color-node.json
}

deploy_color_vrouter() {
  cat <<EOF >${OUT_DIR}/color-router.json
{
  "spec": {
    "listeners": [
      {
        "portMapping": {
          "port": 8080,
	        "protocol": "http"
	      }
      }
    ]
  }
}
EOF

  aws appmesh-preview describe-virtual-router \
    --mesh-name ${MESH_NAME} \
    --virtual-router-name color-router >/dev/null 2>&1 ||
    aws appmesh-preview create-virtual-router \
      --mesh-name ${MESH_NAME} \
      --virtual-router-name color-router \
      --cli-input-json file://${OUT_DIR}/color-router.json
}

deploy_color_vservice() {
  cat <<EOF >${OUT_DIR}/color-service.json
{
  "spec": {
    "provider": {
      "virtualRouter": {
        "virtualRouterName": "color-router"
      }
    }
  }
}
EOF
  color_service_name="color.${DNS_NAMESPACE_NAME}"

  aws appmesh-preview describe-virtual-service \
    --mesh-name ${MESH_NAME} \
    --virtual-service-name color.${DNS_NAMESPACE_NAME} >/dev/null 2>&1 ||
    aws appmesh-preview create-virtual-service \
      --mesh-name ${MESH_NAME} \
      --virtual-service-name ${color_service_name} \
      --cli-input-json file://${OUT_DIR}/color-service.json
}

deploy_color_routes() {
  cat <<EOF >${OUT_DIR}/color-route.json
{
  "virtualRouterName": "color-router",
  "routeName": "color-route",
  "spec": {
    "httpRoute": {
      "match": {
        "prefix": "/"
      },
      "action": {
        "weightedTargets": [
          {
            "virtualNode": "color-node",
            "weight": 100
          }
        ]
      }
    }
  }
}
EOF

  aws appmesh-preview describe-route \
    --mesh-name ${MESH_NAME} \
    --virtual-router-name color-router >/dev/null 2>&1 ||
    aws appmesh-preview create-route \
      --mesh-name ${MESH_NAME} \
      --virtual-router-name color-router \
      --cli-input-json file://${OUT_DIR}/color-route.json
}

deploy_app() {
  OUT_DIR=${DIR}/_output
  mkdir -p ${OUT_DIR}
  deploy_color_vnode
  deploy_color_vrouter
  
  #ENABLE the following to trigger bug
  #deploy_color_routes

  deploy_color_vservice
  deploy_front_vnode

  aws cloudformation deploy \
    --no-fail-on-empty-changeset \
    --stack-name "${PROJECT_NAME}-app" \
    --template-file "${DIR}/app.yaml" \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
    "ProjectName=${PROJECT_NAME}" \
    "EnvoyImage=${ENVOY_IMAGE}" \
    "ColorAppImage=${ECR_IMAGE_PREFIX}/colorapp" \
    "FrontAppImage=${ECR_IMAGE_PREFIX}/feapp" \
    "MeshName=${MESH_NAME}" \
    "ColorVirtualNodeName=color-node" \
    "ColorVirtualServiceName=${color_service_name}" \
    "FrontVirtualNodeName=front-node"
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
    --stack-name="${PROJECT_NAME}-app" \
    --query="Stacks[0].Outputs[?OutputKey=='FrontEndpoint'].OutputValue" \
    --output=text)
  echo "${prefix}/color"
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
