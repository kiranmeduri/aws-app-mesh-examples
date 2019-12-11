#!/bin/bash

set -e

if [ -z $AWS_DEFAULT_REGION ]; then
    echo "AWS_DEFAULT_REGION environment variable is not set."
    exit 1
fi

if [ -z $EKS_CLUSTER_NAME ]; then
    echo "EKS cluster name to setup fargateprofile"
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
PROJECT_NAME="$(basename ${DIR})"
APP_NAMESPACE=${PROJECT_NAME}

eksctl create fargateprofile \
    --cluster $EKS_CLUSTER_NAME \
    --region $AWS_DEFAULT_REGION \
    --namespace $PROJECT_NAME \
    --name $PROJECT_NAME || echo "already exists?"
    
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --region $AWS_DEFAULT_REGION \
    --namespace $PROJECT_NAME \
    --name appmesh-pod \
    --attach-policy-arn arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess arn:aws:iam::aws:policy/AWSCloudMapDiscoverInstanceAccess arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
    --override-existing-serviceaccounts \
    --approve || echo "already exists?"