## Overview
This tutorial shows how ECS tasks using Bridge networking mode can use App Mesh with Envoy as sidecar.

## Bootstrap

1. Clone this repository and navigate to the walkthrough/howto-basics folder, all commands will be ran from this location
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

## Deploy

Run the following:

```
$ ./deploy.sh
...
...
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - appmesh-howto-basics
Public endpoint:
http://appme-.....us-west-2.elb.amazonaws.com/color
```

## Teardown
When you are done with the example you can delete everything we created by running:

```
./deploy.sh delete
```
