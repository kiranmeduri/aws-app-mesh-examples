#!/usr/bin/env bash

set -e

if [ -z $ECS_CLUSTER ]; then
    echo "ECS_CLUSTER environment variable is not set."
    exit 1
fi

if [ -z $COLOR_ECS_SERVICE ]; then
    echo "COLOR_ECS_SERVICE environment variable is not set."
    exit 1
fi

if [ -z $COLOR_FQDN ]; then
    echo "COLOR_FQDN environment variable is not set."
    exit 1
fi

if [ -z $COLOR_PORT ]; then
    echo "COLOR_PORT environment variable is not set."
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"

generate_config() {
    taskArn=$(aws ecs list-tasks \
        --cluster $ECS_CLUSTER \
        --service $COLOR_ECS_SERVICE \
        --output text \
        --query "taskArns[0]")
    containerInstanceArn=$(aws ecs describe-tasks \
        --cluster $ECS_CLUSTER \
        --task $taskArn \
        --output text \
        --query "tasks[0].containerInstanceArn")
    ec2InstanceId=$(aws ecs describe-container-instances \
        --cluster $ECS_CLUSTER \
        --container-instance $containerInstanceArn \
        --output text \
        --query "containerInstances[0].ec2InstanceId")
    ipv6Address=$(aws ec2 describe-instances \
        --instance $ec2InstanceId \
        --output text \
        --query "Reservations[0].Instances[0].NetworkInterfaces[0].Ipv6Addresses[0].Ipv6Address")

    cat ${DIR}/envoy-config.json.sample |
        sed -e "s@COLOR_SERVICE_FQDN@${COLOR_FQDN}@" |
        sed -e "s@COLOR_SERVICE_PORT@${COLOR_PORT}@" |
        sed -e "s@COLOR_ENDPOINT_IP@${ipv6Address}@" |
        sed -e "s@COLOR_ENDPOINT_PORT@15000@" \
            >${DIR}/envoy-config.json

    echo "generated envoy config available at ${DIR}/envoy-config.json"
}

generate_config
sleep 100000000d
