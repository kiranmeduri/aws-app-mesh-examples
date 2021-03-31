## Overview
When migrating from a monolithic architecture to microservices architecture users prefer to employ "strangler" pattern. In this pattern, all requests are destined to same endpoint and based on some aspect of the request the traffic is automatically routed to a particular microservice. In this walkthrough, we will introduce a local sidecar proxy that will receive all requests from locally running app and then forwards traffic to destination service using a custom HTTP header (X-DST-SVC). 

## Prerequisites
1. [Walkthrough: App Mesh with EKS](../eks/)

2. v1beta2 example manifest requires [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) version [>=v1.0.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/releases/tag/v1.0.0). Run the following to check the version of controller you are running.
```
$ kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1
```

You can use v1beta1 example manifest with [aws-app-mesh-controller-for-k8s](https://github.com/aws/aws-app-mesh-controller-for-k8s) version [=v0.3.0](https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/legacy-controller/CHANGELOG.md)

3. Install Docker. It is needed to build the demo application images.

```
## Setup

1. Clone this repository and navigate to the walkthrough/howto-k8s-vsvc-proxy folder, all commands will be ran from this location
2. **Your** account id:

    export AWS_ACCOUNT_ID=<your_account_id>

3. **Region** e.g. us-west-2

    export AWS_DEFAULT_REGION=us-west-2

4. **(Optional) Specify Envoy Image version** If you'd like to use a different Envoy image version than the [default](https://github.com/aws/eks-charts/tree/master/stable/appmesh-controller#configuration), run `helm upgrade` to override the `sidecar.image.repository` and `sidecar.image.tag` fields.

5. Deploy
    ```.
    ./deploy.sh
```

## Using curl to test

Add a curler on your cluster -
```
kubectl run -it curler --image=tutum/curl /bin/bash
```

Run the commands on curler to test.

Requesting blue color -
```
curl front.howto-k8s-vsvc-proxy.svc.cluster.local:8080/color; echo;
```
