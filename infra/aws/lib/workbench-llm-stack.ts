import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

const INSTANCE_TYPE = "g6.xlarge";
const SPOT = "spot";
const ON_DEMAND = "on-demand";
// The AMI snapshot size. It leaves room for two models, and the 24 GB card
// caps a usable model near 20 GB, so more disk buys nothing.
const DISK_GIB = 75;
const INSTANCE_NAME = "agent-workbench-gpu-llm";
export const LLM_MODEL = "qwen3.8:27b";
const TAILSCALE_AUTH_KEY_PARAMETER =
  "/coding-agent-workbench/tailscale/llm-auth-key";
const DEFAULT_REPO_URL =
  "https://github.com/BrentGrammer/ai-coding-agent-workbench.git";
// Ships the NVIDIA driver, so setup-llm.sh installs no driver and never
// reboots. Confirm and override: docs/cloud-onetime-setup.md#6-gpu-ami.
const DEFAULT_GPU_AMI_PARAMETER =
  "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-22.04/latest/ami-id";

export interface WorkbenchLlmStackProps extends cdk.StackProps {
  cacheBucket: s3.IBucket;
}

export class WorkbenchLlmStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WorkbenchLlmStackProps) {
    super(scope, id, props);

    const repoUrl =
      (this.node.tryGetContext("repoUrl") as string) ?? DEFAULT_REPO_URL;
    const amiParameter =
      (this.node.tryGetContext("llmAmiParameter") as string) ??
      DEFAULT_GPU_AMI_PARAMETER;
    const purchaseOption =
      (this.node.tryGetContext("llmPurchaseOption") as string) ?? SPOT;
    if (purchaseOption !== SPOT && purchaseOption !== ON_DEMAND) {
      throw new Error(
        `llmPurchaseOption must be "${SPOT}" or "${ON_DEMAND}"`,
      );
    }
    const useSpot = purchaseOption === SPOT;

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

    const launchTemplate = new ec2.LaunchTemplate(this, "LaunchTemplate", {
      instanceType: new ec2.InstanceType(INSTANCE_TYPE),
      machineImage: ec2.MachineImage.fromSsmParameter(amiParameter, {
        os: ec2.OperatingSystemType.LINUX,
      }),
      role,
      securityGroup,
      userData,
      associatePublicIpAddress: true,
      instanceInitiatedShutdownBehavior:
        ec2.InstanceInitiatedShutdownBehavior.TERMINATE,
      requireImdsv2: true,
      httpPutResponseHopLimit: 1,
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
    cdk.Tags.of(launchTemplate).add("Name", INSTANCE_NAME);

    const fleet = new ec2.CfnEC2Fleet(this, "LlmFleet", {
      type: "instant",
      launchTemplateConfigs: [
        {
          launchTemplateSpecification: {
            launchTemplateId: launchTemplate.launchTemplateId,
            version: launchTemplate.latestVersionNumber,
          },
          overrides: vpc.publicSubnets.map((subnet) => ({
            subnetId: subnet.subnetId,
          })),
        },
      ],
      spotOptions: useSpot
        ? {
            allocationStrategy: "price-capacity-optimized",
            instanceInterruptionBehavior: "terminate",
          }
        : undefined,
      targetCapacitySpecification: {
        defaultTargetCapacityType: purchaseOption,
        onDemandTargetCapacity: useSpot ? 0 : 1,
        spotTargetCapacity: useSpot ? 1 : 0,
        totalTargetCapacity: 1,
      },
    });

    new cdk.CfnOutput(this, "FleetId", { value: fleet.attrFleetId });
  }
}
