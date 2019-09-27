## Overview
This example shows how to use front-proxy pattern with App Mesh. This is currently unsupported by App Mesh and just for the purposes of hacking through.

In this setup we have the following:

1. Two backend ECS services B1 and B2 registered as virtual-nodes with App Mesh. 
2. A front-proxy ECS service that uses Envoy in standalone mode (instead of sidecar) to route incoming traffic to B1 and B2 using path prefix match /b1 and /b2 respectively. 

To make front-proxy do its thing we will configure the following:

1. Create a internet-facing NLB. This will be our entry @ edge.
2. Create a virtual-router for front-proxy with routes /b1 to B1 virtual-node and /b2 to B2 virtual-node
3. Create a virtual-service with front-proxy virtual-router as provider. Name it with NLB's DNS name.
4. Create a front-proxy virtual-node with backends = NLB's DNS name.
5. Create a custom bootstrap Envoy config which derives most of the configuration from App Mesh envoy used for backend services. Only difference being the listeners are statically defined and LDS is not configured. This special listener will listen to incoming traffic from NLB and use the routes discovered using RDS (from front-proxy virtual-router). 

## Setup

1. Clone this repository and navigate to the walkthrough/howto-ingress folder, all commands will be ran from this location
2. **Your** account id:
    ```
    export AWS_ACCOUNT_ID=<your_account_id>
    ```
3. **Region** e.g. us-west-2
    ```
    export AWS_DEFAULT_REGION=us-west-2
    ```
4. **ENVOY_IMAGE** environment variable is not set to App Mesh Envoy, see https://docs.aws.amazon.com/app-mesh/latest/userguide/envoy.html
    ```
    export ENVOY_IMAGE=...
    ```
5. Setup using cloudformation
    ```
    ./deploy.sh
    ```