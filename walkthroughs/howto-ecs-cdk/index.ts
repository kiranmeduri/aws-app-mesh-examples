import appmesh = require('@aws-cdk/aws-appmesh');
import ecs = require('@aws-cdk/aws-ecs');
import iam = require('@aws-cdk/aws-iam');
import ec2 = require('@aws-cdk/aws-ec2');
import logs = require('@aws-cdk/aws-logs');
import cdk = require('@aws-cdk/core');
import servicediscovery = require('@aws-cdk/aws-servicediscovery');
import elbv2 = require('@aws-cdk/aws-elasticloadbalancingv2');
import fargateappmeshservice = require('./FargateAppMeshService');
import ecsec2appmeshservice = require('./EcsEc2AppMeshService');

const projectName = "howto-ecs-cdk"
const cloudmapNamespaceName = `${projectName}.local`
const portNumber = 8080
const launchType = "EC2"

class HowToEcsCdkStack extends cdk.Stack {
    constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
        super(scope, id, props);

        const envoyImage = new cdk.CfnParameter(this, "EnvoyImage", {
            type: "String",
            description: "Envoy container image"
        });
        const colorAppImage = new cdk.CfnParameter(this, "ColorAppImage", {
            type: "String",
            description: "Color app container image"
        });
        const frontAppImage = new cdk.CfnParameter(this, "FrontAppImage", {
            type: "String",
            description: "Front app container image"
        });

        //INFRA: vpc
        const vpc = new ec2.Vpc(this, 'vpc', { maxAzs: 2 });

        //INFRA: ecs cluster
        const cluster = new ecs.Cluster(this, 'cluster', { 
            vpc: vpc,
            defaultCloudMapNamespace: {
                name: cloudmapNamespaceName,
                type: servicediscovery.NamespaceType.DNS_PRIVATE,
            }
        });
        if launchType === "EC2" {
            cluster.addCapacity('DefaultAutoScalingGroup', {
                instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5N, ec2.InstanceSize.LARGE)
            });
        }

        //INFRA: appmesh mesh 
        const mesh = new appmesh.Mesh(this, 'mesh', {
            meshName: projectName
        });

        //MIDDLEWARE: task roles
        const executionRole = new iam.Role(this, 'exec-role', {
            assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com')
        });
        executionRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'));
        executionRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'));
        const taskRole = new iam.Role(this, 'task-role', {
            assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com')
        });
        taskRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchFullAccess'));
        taskRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'));
        taskRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AWSAppMeshEnvoyAccess'));

        //MIDDLEWARE: cloudwatch log-group
        const logGroup = new logs.LogGroup(this, 'log-group')

        //APP: 
        var colorService, frontService;
        if launchType === "FARGATE" {
            colorService = new fargateappmeshservice.FargateAppMeshService(this, 'color', {
                cluster: cluster,
                mesh: mesh,
                portNumber: portNumber,
                taskRole: taskRole,
                executionRole: executionRole,
                cloudmapNamespaceName: cloudmapNamespaceName,
                envoyImage: ecs.ContainerImage.fromRegistry(envoyImage.valueAsString),
                logGroup: logGroup,
                enableXRay: true,
                applicationContainerOpts: {
                    image: ecs.ContainerImage.fromRegistry(colorAppImage.valueAsString),
                    memoryLimitMiB: 512,
                    cpu: 256,
                    environment: {
                        PORT: `${portNumber}`,
                        COLOR: 'green',
                    }
                }
            });

            frontService = new fargateappmeshservice.FargateAppMeshService(this, 'front', {
                cluster: cluster,
                mesh: mesh,
                portNumber: portNumber,
                taskRole: taskRole,
                executionRole: executionRole,
                cloudmapNamespaceName: cloudmapNamespaceName,
                envoyImage: ecs.ContainerImage.fromRegistry(envoyImage.valueAsString),
                logGroup: logGroup,
                enableXRay: true,
                applicationContainerOpts: {
                    image: ecs.ContainerImage.fromRegistry(frontAppImage.valueAsString),
                    memoryLimitMiB: 512,
                    cpu: 256,
                    environment: {
                        COLOR_HOST: `color.${cloudmapNamespaceName}:${portNumber}`,
                        PORT: `${portNumber}`
                    }
                }
            });
        }

        frontService.connectToMeshService(colorService);

        const externalLB = new elbv2.ApplicationLoadBalancer(this, 'external', {
            vpc: vpc,
            internetFacing: true
        });

        const externalListener = externalLB.addListener('PublicListener', { port: 80, open: true });

        externalListener.addTargets('front', {
            port: 80,
            healthCheck: {
                path: '/ping'
            },
            targets: [frontService.service]
        });

        new cdk.CfnOutput(this, 'ExternalDNS', {
            exportName: `${projectName}-endpoint`,
            value: externalLB.loadBalancerDnsName
        });
    }
}

const app = new cdk.App();
new HowToEcsCdkStack(app, projectName);

app.synth();
