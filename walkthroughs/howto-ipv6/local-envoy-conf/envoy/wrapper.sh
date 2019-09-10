#!/usr/bin/env bash

set -ex

if [ -z $APP_PORT ]; then
    echo "APP_PORT environment variable is not set."
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
APP_IP=${APP_IP:-"127.0.0.1"}

generate_config() {
    cat ${DIR}/envoy-config.json.sample |
        sed -e "s@APP_IP@${APP_IP}@" |
        sed -e "s@APP_PORT@${APP_PORT}@" \
            >${DIR}/envoy-config.json

    echo "generated envoy config available at ${DIR}/envoy-config.json"
    cat ${DIR}/envoy-config.json
}

generate_config
sleep 100000000d
