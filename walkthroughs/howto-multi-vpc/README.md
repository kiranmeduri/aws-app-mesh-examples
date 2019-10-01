## Overview
This example shows how to use VPC PrivateLink with App Mesh to connect applications across VPC boundary.

In this setup we have the following:

1. Color app running in vpc-1
2. Front app running in vpc-2
3. Color app is added behind NLB to support PrivateLink
4. vpc-2 has VPC endpoint for Front app to communicate with Color app
5. A wildcard Route53 record (*.howto-multi-vpc.mesh.local) to resolve virtual-service names to a fake ip address 1.2.3.4
6. Color app's virtual-node uses VPC endpoint's DNS to support Front app to connect. But this is not right. Color app should be unaware of the VPC endpoint's DNS name and should continue to use Cloud Map etc.

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