import appmesh = require('@aws-cdk/aws-appmesh');
import ecs = require('@aws-cdk/aws-ecs');
import iam = require('@aws-cdk/aws-iam');
import ec2 = require('@aws-cdk/aws-ec2');
import logs = require('@aws-cdk/aws-logs');
import cdk = require('@aws-cdk/core');
import servicediscovery = require('@aws-cdk/aws-servicediscovery');

export interface FargateAppMeshServiceProps {
    cluster: ecs.Cluster;
    mesh: appmesh.Mesh;
    applicationContainerOpts: ecs.ContainerDefinitionOptions;
    taskRole: iam.Role;
    executionRole: iam.Role;
    portNumber: number;
    envoyImage: ecs.ContainerImage;
    cloudmapNamespaceName: string;
    logGroup: logs.ILogGroup;
    enableXRay?: boolean;
}

export class FargateAppMeshService extends cdk.Construct {
    readonly serviceName: string;
    readonly portNumber: number;
    readonly cluster: ecs.Cluster;
    readonly mesh: appmesh.Mesh;
    readonly taskDefinition: ecs.FargateTaskDefinition;
    readonly service: ecs.FargateService;
    readonly virtualNode: appmesh.VirtualNode;
    readonly virtualService: appmesh.VirtualService;

    constructor(scope: cdk.Construct, id: string, props: FargateAppMeshServiceProps) {
        super(scope, id);
        this.cluster = props.cluster;
        this. mesh = props.mesh;
        const applicationContainerOpts = props.applicationContainerOpts;

        this.serviceName = id;
        this.portNumber = props.portNumber;
        const enableXRay = props.enableXRay !== undefined ? props.enableXRay : false

        this.taskDefinition = new ecs.FargateTaskDefinition(this, `${this.serviceName}-task-definition`, {
            taskRole: props.taskRole,
            executionRole: props.executionRole,
            proxyConfiguration: new ecs.AppMeshProxyConfiguration({
                containerName: 'envoy',
                properties: {
                    appPorts: [this.portNumber],
                    proxyEgressPort: 15001,
                    proxyIngressPort: 15000,
                    ignoredUID: 1337,
                    egressIgnoredIPs: [
                        '169.254.170.2',
                        '169.254.169.254'
                    ]
                }
            })
        });

        var applicationContainer = this.taskDefinition.addContainer('app', {
            ...applicationContainerOpts,
            logging: new ecs.AwsLogDriver({
                streamPrefix: this.serviceName,
                logGroup: props.logGroup
            })
        });
        applicationContainer.addPortMappings({
            containerPort: this.portNumber,
            hostPort: this.portNumber
        });

        var envoyContainer = this.taskDefinition.addContainer('envoy', {
            image: props.envoyImage,
            essential: true,
            environment: {
                APPMESH_VIRTUAL_NODE_NAME: `mesh/${this.mesh.meshName}/virtualNode/${this.serviceName}`,
                AWS_REGION: cdk.Stack.of(this).region,
                ENABLE_ENVOY_XRAY_TRACING: enableXRay ? '1' : '0',
                ENABLE_ENVOY_STATS_TAGS: '1',
                ENABLE_ENVOY_DOG_STATSD: '1',
                ENVOY_LOG_LEVEL: 'debug'
            },
            healthCheck: {
                command: [
                    'CMD-SHELL',
                    'curl -s http://localhost:9901/server_info | grep state | grep -q LIVE'
                ],
                startPeriod: cdk.Duration.seconds(10),
                interval: cdk.Duration.seconds(5),
                timeout: cdk.Duration.seconds(2),
                retries: 3
            },
            memoryLimitMiB: 128,
            user: '1337',
            logging: new ecs.AwsLogDriver({
                streamPrefix: this.serviceName,
                logGroup: props.logGroup
            })
        });
        
        applicationContainer.addContainerDependencies({
            container: envoyContainer,
            condition: ecs.ContainerDependencyCondition.HEALTHY
        });

        if (enableXRay) {
            var xrayContainer = this.taskDefinition.addContainer('xray', {
                image: ecs.ContainerImage.fromRegistry('amazon/aws-xray-daemon'),
                essential: true,
                user: '1337'
            });
            envoyContainer.addContainerDependencies({
                container: xrayContainer,
                condition: ecs.ContainerDependencyCondition.START
            });

            applicationContainer.addContainerDependencies({
                container: xrayContainer,
                condition: ecs.ContainerDependencyCondition.START
            });
        }

        this.service = new ecs.FargateService(this, `${this.serviceName}-service`, {
            cluster: this.cluster,
            desiredCount: 2,
            taskDefinition: this.taskDefinition,
            cloudMapOptions: {
                dnsRecordType: servicediscovery.DnsRecordType.A,
                dnsTtl: cdk.Duration.seconds(10),
                failureThreshold: 2,
                name: this.serviceName
            }
        });
        
        // Create a virtual node for the name service
        this.virtualNode = new appmesh.VirtualNode(this, `${this.serviceName}-virtual-node`, {
            mesh: this.mesh,
            virtualNodeName: this.serviceName,
            cloudMapService: this.service.cloudMapService,
            listener: {
                portMapping: {
                    port: this.portNumber,
                    protocol: appmesh.Protocol.HTTP,
                }
            },
        });

        // Create virtual service to make the virtual node accessible
        this.virtualService = new appmesh.VirtualService(this, `${this.serviceName}-virtual-service`, {
            mesh: this.mesh,
            virtualNode: this.virtualNode,
            virtualServiceName: `${this.serviceName}.${props.cloudmapNamespaceName}`
        });
    }

    // Connect this mesh enabled service to another mesh enabled service.
    // This adjusts the security groups for both services so that they
    // can talk to each other. Also adjusts the virtual node for this service
    // so that its Envoy intercepts traffic that can be handled by the other
    // service's virtual service.
    connectToMeshService(appMeshService: FargateAppMeshService) {
        var trafficPort = ec2.Port.tcp(appMeshService.portNumber);

        // Adjust security group to allow traffic from this app mesh enabled service
        // to the other app mesh enabled service.
        this.service.connections.allowTo(appMeshService.service, trafficPort, `Inbound traffic from the app mesh enabled ${this.serviceName}`);

        // Now adjust this app mesh service's virtual node to add a backend
        // that is the other service's virtual service
        this.virtualNode.addBackends(appMeshService.virtualService);
    } 
}
