import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

const INSTANCE_TYPE = "g6.xlarge";
const DISK_GIB = 60;
const INSTANCE_NAME = "agent-workbench-gpu-llm";
const LLM_MODEL = "qwen3.8:27b";
const TAILSCALE_AUTH_KEY_PARAMETER =
  "/coding-agent-workbench/tailscale/llm-auth-key";
const DEFAULT_REPO_URL =
  "https://github.com/BrentGrammer/ai-coding-agent-workbench.git";
const UBUNTU_2404_AMD64_AMI_PARAMETER =
  "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id";

export interface WorkbenchLlmStackProps extends cdk.StackProps {
  cacheBucket: s3.IBucket;
}

export class WorkbenchLlmStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WorkbenchLlmStackProps) {
    super(scope, id, props);

    const repoUrl =
      (this.node.tryGetContext("repoUrl") as string) ?? DEFAULT_REPO_URL;

    const vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", { isDefault: true });

    const securityGroup = new ec2.SecurityGroup(this, "LlmSecurityGroup", {
      vpc,
      description: "Agent LLM. No inbound; Tailscale and SSM go outbound.",
      allowAllOutbound: true,
    });

    const role = new iam.Role(this, "LlmInstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      description:
        "Lets the LLM instance use SSM, read the Tailscale key, and use the model cache bucket.",
    });
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
    );
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: ["ssm:GetParameter"],
        resources: [
          this.formatArn({
            service: "ssm",
            resource: "parameter",
            resourceName: TAILSCALE_AUTH_KEY_PARAMETER.replace(/^\//, ""),
          }),
        ],
      }),
    );
    props.cacheBucket.grantReadWrite(role);

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      "set -euo pipefail",
      "hostnamectl set-hostname agent-llm",
      "mkdir -p /etc/agent-workbench",
      `printf 'AWS_REGION=%s\\nLLM_CACHE_BUCKET=%s\\nLLM_MODEL=%s\\n' '${this.region}' '${props.cacheBucket.bucketName}' '${LLM_MODEL}' > /etc/agent-workbench/workbench.env`,
      "chmod 644 /etc/agent-workbench/workbench.env",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get install -y git",
      `[ -d /opt/agent-workbench/.git ] || git clone --branch main ${repoUrl} /opt/agent-workbench`,
      "chown -R root:root /opt/agent-workbench",
      "bash /opt/agent-workbench/infra/aws/ec2/setup-llm.sh",
    );

    const launchTemplate = new ec2.CfnLaunchTemplate(this, "LaunchTemplate", {
      launchTemplateData: {
        metadataOptions: {
          httpTokens: "required",
          httpPutResponseHopLimit: 1,
        },
        instanceMarketOptions: {
          marketType: "spot",
          spotOptions: {
            spotInstanceType: "one-time",
            instanceInterruptionBehavior: "terminate",
          },
        },
      },
    });

    const instance = new ec2.Instance(this, "LlmInstance", {
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      instanceType: new ec2.InstanceType(INSTANCE_TYPE),
      machineImage: ec2.MachineImage.fromSsmParameter(
        UBUNTU_2404_AMD64_AMI_PARAMETER,
        { os: ec2.OperatingSystemType.LINUX },
      ),
      role,
      securityGroup,
      userData,
      associatePublicIpAddress: true,
      // Spot one-time cannot stop. shutdown must terminate so billing ends.
      instanceInitiatedShutdownBehavior:
        ec2.InstanceInitiatedShutdownBehavior.TERMINATE,
      blockDevices: [
        {
          deviceName: "/dev/sda1",
          volume: ec2.BlockDeviceVolume.ebs(DISK_GIB, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            deleteOnTermination: true,
          }),
        },
      ],
    });
    instance.instance.launchTemplate = {
      launchTemplateId: launchTemplate.ref,
      version: launchTemplate.attrLatestVersionNumber,
    };
    cdk.Tags.of(instance).add("Name", INSTANCE_NAME);

    new cdk.CfnOutput(this, "InstanceId", { value: instance.instanceId });
  }
}
