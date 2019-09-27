#!/bin/sh -e

sleep ${APPMESH_SLEEP_DURATION:-0}

APPMESH_PREVIEW=${APPMESH_PREVIEW:-0}
APPMESH_VERBOSE=${APPMESH_VERBOSE:-0}
ENABLE_ENVOY_XRAY_TRACING=${ENABLE_ENVOY_XRAY_TRACING:-0}
ENABLE_ENVOY_DOG_STATSD=${ENABLE_ENVOY_DOG_STATSD:=0}
ENABLE_ENVOY_STATS_TAGS=${ENABLE_ENVOY_STATS_TAGS:=0}
ENVOY_CONFIG_FILE=${ENVOY_CONFIG_FILE:-/tmp/envoy.yaml}
ENVOY_ADMIN_ACCESS_LOG_FILE=${ENVOY_ADMIN_ACCESS_LOG_FILE:-/tmp/envoy_admin_access.log}
ENVOY_ADMIN_ACCESS_PORT=${ENVOY_ADMIN_ACCESS_PORT:-9901}
ENVOY_LOG_LEVEL=${ENVOY_LOG_LEVEL:-info}
ENVOY_MAX_OBJ_NAME=${ENVOY_MAX_OBJ_NAME:-500}

function generate_main_envoy_config() {

    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(curl --connect-timeout 2 -s "http://169.254.169.254/latest/meta-data/placement/availability-zone" | sed 's/[a-z]$//')
        [ -z "$AWS_REGION" ] && echo "AWS region could not be found or was not set in AWS_REGION environment variable." && exit 1
    fi

    if [ "$APPMESH_PREVIEW" -eq 1 ]; then
        APPMESH_XDS_ENDPOINT=${APPMESH_XDS_ENDPOINT:-appmesh-preview-envoy-management.$AWS_REGION.amazonaws.com:443}
    else
        APPMESH_XDS_ENDPOINT=${APPMESH_XDS_ENDPOINT:-appmesh-envoy-management.$AWS_REGION.amazonaws.com:443}
    fi

    if [ "$APPMESH_PREVIEW" -eq 1 ]; then
        APPMESH_SIGNING_NAME=${APPMESH_SIGNING_NAME:-appmesh-preview}
    else
        APPMESH_SIGNING_NAME=${APPMESH_SIGNING_NAME:-appmesh}
    fi

    [ -z "$APPMESH_VIRTUAL_NODE_NAME" ] && echo "APPMESH_VIRTUAL_NODE_NAME environment variable not set." && exit 1
    APPMESH_VIRTUAL_NODE_CLUSTER=${APPMESH_VIRTUAL_NODE_CLUSTER:-$APPMESH_VIRTUAL_NODE_NAME}

    cat << CONFIG_EOF > "$ENVOY_CONFIG_FILE"
admin:
  access_log_path: $ENVOY_ADMIN_ACCESS_LOG_FILE
  # Provides access to: http://<envoy hostname>:$ENVOY_ADMIN_ACCESS_PORT/config_dump
  address:
    socket_address: { address: 0.0.0.0, port_value: $ENVOY_ADMIN_ACCESS_PORT }

node:
    id: $APPMESH_VIRTUAL_NODE_NAME
    cluster: $APPMESH_VIRTUAL_NODE_CLUSTER

CONFIG_EOF

    if [ "$APPMESH_GATEWAY" -eq 1 ]; then
        generate_gateway_config
    else
        generate_sidecar_config
    fi
}

function generate_sidecar_config() {
    cat << CONFIG_EOF >> "$ENVOY_CONFIG_FILE"
dynamic_resources:
  # Configure Envoy to get listeners and clusters via GRPC ADS
  ads_config:
    api_type: GRPC
    grpc_services:
      google_grpc:
        target_uri: $APPMESH_XDS_ENDPOINT
        stat_prefix: ads
        channel_credentials:
          ssl_credentials:
            root_certs:
              filename: /etc/pki/tls/cert.pem
        credentials_factory_name: envoy.grpc_credentials.aws_iam
        call_credentials:
          from_plugin:
            name: envoy.grpc_credentials.aws_iam
            config:
              region: $AWS_REGION
              service_name: $APPMESH_SIGNING_NAME
  lds_config: {ads: {}}
  cds_config: {ads: {}}

CONFIG_EOF
}

function generate_gateway_config() {
    [ -z "$APPMESH_GATEWAY_LISTEN_PORT" ] && echo "APPMESH_GATEWAY_LISTEN_PORT environment variable not set." && exit 1
    [ -z "$APPMESH_GATEWAY_PING_PORT" ] && echo "APPMESH_GATEWAY_PING_PORT environment variable not set." && exit 1

cat << CONFIG_EOF >> "$ENVOY_CONFIG_FILE"
dynamic_resources:
  # Configure Envoy to get listeners and clusters via GRPC ADS
  ads_config:
    api_type: GRPC
    grpc_services:
      google_grpc:
        target_uri: $APPMESH_XDS_ENDPOINT
        stat_prefix: ads
        channel_credentials:
          ssl_credentials:
            root_certs:
              filename: /etc/pki/tls/cert.pem
        credentials_factory_name: envoy.grpc_credentials.aws_iam
        call_credentials:
          from_plugin:
            name: envoy.grpc_credentials.aws_iam
            config:
              region: $AWS_REGION
              service_name: $APPMESH_SIGNING_NAME
  cds_config: {ads: {}}

static_resources:
    listeners:
        - name: ingress
          address:
              socket_address:
                  address: 0.0.0.0
                  port_value: $APPMESH_GATEWAY_LISTEN_PORT
          filter_chains:
              - filters:
                    - name: envoy.http_connection_manager
                      config:
                          tracing: {}
                          http_filters:
                              - name: envoy.router
                          rds:
                              config_source:
                                  ads: {}
                              route_config_name: rds_egress_http_$APPMESH_GATEWAY_LISTEN_PORT
                          stat_prefix: ingress
          listener_filters:
              - name: envoy.listener.tls_inspector
        - name: ping
          address:
              socket_address:
                  address: 0.0.0.0
                  port_value: $APPMESH_GATEWAY_PING_PORT
          filter_chains:
              - filters:
                    - name: envoy.http_connection_manager
                      config:
                          tracing: {}
                          http_filters:
                              - name: envoy.router
                          route_config:
                              name: route_ping
                              virtual_hosts:
                                  - name: ping
                                    domains:
                                        - "*"
                                    routes:
                                        - match:
                                              prefix: /
                                          direct_response:
                                              status: 200
                                              body:
                                                  inline_string: pong
                          stat_prefix: ingress
          listener_filters:
              - name: envoy.listener.tls_inspector

CONFIG_EOF
}

function append_envoy_config_extension() {
    if [ -f "$1" ]; then
        echo "Appending $1 to $ENVOY_CONFIG_FILE"
        echo >> "$ENVOY_CONFIG_FILE"
        cat "$1" >> "$ENVOY_CONFIG_FILE"
    fi
}

function generate_envoy_tracing_config() {
    if [ "$ENABLE_ENVOY_XRAY_TRACING" -eq 1 ]; then
        if [ -n "$ENVOY_TRACING_CFG_FILE" ]; then
            echo "$ENVOY_TRACING_CFG_FILE is defined, skipping generating envoy.xray tracing config"
            return
        fi
        ENVOY_TRACING_CFG_FILE="/tmp/envoy_tracing_config.yaml"
        XRAY_DAEMON_PORT=${XRAY_DAEMON_PORT:-2000}
        AWS_XRAY_DAEMON_ADDRESS="${AWS_XRAY_DAEMON_ADDRESS:-127.0.0.1:$XRAY_DAEMON_PORT}"

        cat << CONFIG_EOF > "$ENVOY_TRACING_CFG_FILE"
tracing:
  http:
    name: envoy.xray
    config:
      daemon_endpoint: "${AWS_XRAY_DAEMON_ADDRESS}"
CONFIG_EOF

    echo "added envoy.xray tracing config to $ENVOY_TRACING_CFG_FILE"

    fi
}

function generate_envoy_stats_sinks_config() {
    if [ "$ENABLE_ENVOY_DOG_STATSD" -eq 1 ]; then
        if [ -n "$ENVOY_STATS_SINKS_CFG_FILE" ]; then
            echo "$ENVOY_STATS_SINKS_CFG_FILE is defined, skipping generating stats_sinks config"
            return
        fi
        ENVOY_STATS_SINKS_CFG_FILE="/tmp/envoy_stats_sinks_config.yaml"
        STATSD_PORT=${STATSD_PORT:-8125}
        cat << CONFIG_EOF > "$ENVOY_STATS_SINKS_CFG_FILE"
stats_sinks:
  - name: envoy.dog_statsd
    config:
      address:
        socket_address:
          protocol: udp
          address: 127.0.0.1
          port_value: ${STATSD_PORT}

CONFIG_EOF

    fi
}

function generate_envoy_stats_config() {
    if [ "$ENABLE_ENVOY_STATS_TAGS" -eq 1 ]; then
        if [ -n "$ENVOY_STATS_CONFIG_FILE" ]; then
            echo "$ENVOY_STATS_CONFIG_FILE is defined, skipping generating stats_tags config"
            return
        fi
        ENVOY_STATS_CONFIG_FILE="/tmp/envoy_stats_config.yaml"
        APPMESH_MESH_TAG=`echo ${APPMESH_VIRTUAL_NODE_NAME} | sed 's#mesh/\(.*\)/virtualNode/\(.*\)#\1#'`
        APPMESH_VIRTUAL_NODE_TAG=`echo ${APPMESH_VIRTUAL_NODE_NAME} | sed 's#mesh/\(.*\)/virtualNode/\(.*\)#\2#'`
        cat << CONFIG_EOF > "$ENVOY_STATS_CONFIG_FILE"
stats_config:
  stats_tags:
    - tag_name: "appmesh.mesh"
      fixed_value: "${APPMESH_MESH_TAG}"
    - tag_name: "appmesh.virtual_node"
      fixed_value: "${APPMESH_VIRTUAL_NODE_TAG}"
CONFIG_EOF

    fi
}

function process_envoy_config_extensions() {
    generate_envoy_tracing_config
    append_envoy_config_extension "$ENVOY_TRACING_CFG_FILE"
    generate_envoy_stats_config
    append_envoy_config_extension "$ENVOY_STATS_CONFIG_FILE"
    generate_envoy_stats_sinks_config
    append_envoy_config_extension "$ENVOY_STATS_SINKS_CFG_FILE"

    if [ ! -z "$ENVOY_STATS_FLUSH_INTERVAL" ]; then
        echo >> "$ENVOY_CONFIG_FILE"
        echo "stats_flush_interval: $ENVOY_STATS_FLUSH_INTERVAL" >> "$ENVOY_CONFIG_FILE"
    fi
}

function dump_variables() {
    if [ "$APPMESH_VERBOSE" -eq 1 ]; then
        echo "=== Envoy variables ==="
        env | grep ENVOY_ || true
        echo "==="
        echo

        echo "=== AppMesh variables ==="
        env | grep APPMESH_ || true
        echo "==="
        echo
    fi
}

function configure() {
    if [ ! -f "$ENVOY_CONFIG_FILE" ]; then
        echo "Did not find Envoy configuration file at $ENVOY_CONFIG_FILE, creating one."
        generate_main_envoy_config
        process_envoy_config_extensions
    else
        echo "Using existing Envoy configuration file at $ENVOY_CONFIG_FILE."
    fi
}

function dump_config() {
    if [ "$APPMESH_VERBOSE" -eq 1 ]; then
        echo
        echo "=== Envoy config ==="
        cat "$ENVOY_CONFIG_FILE"
        echo "==="
        echo
    fi
}

dump_variables
configure
dump_config

if [ -x /opt/amazon/bin/sidecar-proxy-route-manager.sh ]; then
    echo "Performing one-off route setup."
    echo "quit" | /usr/bin/env APPMESH_START_ENABLED=1 sudo -E /opt/amazon/bin/sidecar-proxy-route-manager.sh
fi

echo "Starting Envoy."
exec /usr/bin/envoy \
    -c "$ENVOY_CONFIG_FILE" \
    --log-level "$ENVOY_LOG_LEVEL" \
    --max-obj-name-len $ENVOY_MAX_OBJ_NAME
