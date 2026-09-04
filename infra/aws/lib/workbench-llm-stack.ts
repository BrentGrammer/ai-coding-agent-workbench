import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";
import {
  addBoxFilesInstall,
  boxFilesAsset,
  denyParameterStoreReads,
  grantBoxFilesRead,
} from "./box-files";

// L40S, 48 GB VRAM: fits the model plus a 131K q8_0 KV cache. Override with
// -c llmInstanceType, or WORKBENCH_LLM_INSTANCE_TYPE through bin/workbench.
const DEFAULT_INSTANCE_TYPE = "g6e.xlarge";
// The KV cache costs ~128 KB/token: ~48K fits a 24 GB card, ~200K a 48 GB one.
// Override with -c llmContextLength, or WORKBENCH_LLM_CONTEXT_LENGTH.
const DEFAULT_CONTEXT_LENGTH = 131072;
// q8_0 halves the KV cache so it fits the 24 GB floor card. f16 keeps full
// quality at long context but needs a 48 GB card.
const DEFAULT_KV_CACHE_TYPE = "q8_0";
const SPOT = "spot";
const ON_DEMAND = "on-demand";
// The AMI snapshot size. It leaves room for two models, since a single card
// caps a usable model near its VRAM size.
const DISK_GIB = 75;
const INSTANCE_NAME = "aws-native-agent-workbench-gpu-llm";
export const LLM_MODEL = "qwen3.8:27b";
// Ships the NVIDIA driver, so setup-llm.sh installs no driver and never
// reboots. Confirm and override: docs/cloud-onetime-setup.md#6-gpu-ami.
const DEFAULT_GPU_AMI_PARAMETER =
  "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-22.04/latest/ami-id";

export interface WorkbenchLlmStackProps extends cdk.StackProps {
  cacheBucket: s3.IBucket;
  workbenchSecurityGroups: ec2.ISecurityGroup[];
}

export class WorkbenchLlmStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WorkbenchLlmStackProps) {
    super(scope, id, props);

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
    const instanceType =
      (this.node.tryGetContext("llmInstanceType") as string) ??
      DEFAULT_INSTANCE_TYPE;
    const contextLength = Number(
      this.node.tryGetContext("llmContextLength") ?? DEFAULT_CONTEXT_LENGTH,
    );
    if (!Number.isInteger(contextLength) || contextLength <= 0) {
      throw new Error("llmContextLength must be a positive integer");
    }
    const kvCacheType =
      (this.node.tryGetContext("llmKvCacheType") as string) ??
      DEFAULT_KV_CACHE_TYPE;
    if (kvCacheType !== "q8_0" && kvCacheType !== "f16") {
      throw new Error('llmKvCacheType must be "q8_0" or "f16"');
    }

    const vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", { isDefault: true });

    if (props.workbenchSecurityGroups.length === 0) {
      throw new Error("workbenchSecurityGroups must not be empty");
    }

    const securityGroup = new ec2.SecurityGroup(this, "LlmSecurityGroup", {
      vpc,
      description: "Agent LLM. Inference is reachable only from the workbench.",
      allowAllOutbound: true,
    });
    for (const workbenchSecurityGroup of props.workbenchSecurityGroups) {
      securityGroup.addIngressRule(
        workbenchSecurityGroup,
        ec2.Port.tcp(11435),
        "Inference from a workbench",
      );
    }

    const role = new iam.Role(this, "LlmInstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      description:
        "Lets the LLM instance use SSM and the model cache bucket.",
    });
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
    );
    props.cacheBucket.grantReadWrite(role);
    role.addToPolicy(denyParameterStoreReads());

    const asset = boxFilesAsset(this);
    grantBoxFilesRead(asset, role);

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      "set -euo pipefail",
      "hostnamectl set-hostname aws-native-agent-llm",
      "mkdir -p /etc/agent-workbench",
      `printf 'AWS_REGION=%s\\nLLM_CACHE_BUCKET=%s\\nLLM_MODEL=%s\\nOLLAMA_CONTEXT_LENGTH=%s\\nOLLAMA_KV_CACHE_TYPE=%s\\n' '${this.region}' '${props.cacheBucket.bucketName}' '${LLM_MODEL}' '${contextLength}' '${kvCacheType}' > /etc/agent-workbench/workbench.env`,
      "chmod 644 /etc/agent-workbench/workbench.env",
    );
    addBoxFilesInstall(userData, asset);
    userData.addCommands(
      "bash /opt/agent-workbench/infra/aws/ec2/setup-llm.sh",
    );

    const launchTemplate = new ec2.LaunchTemplate(this, "LaunchTemplate", {
      instanceType: new ec2.InstanceType(instanceType),
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
            // Loading 15 GB into VRAM is disk-bound. Defaults of 3000/125 cost
            // three minutes. Provisioned capacity bills hourly, so this is cents.
            iops: 6000,
            throughput: 750,
            encrypted: true,
            deleteOnTermination: true,
          }),
        },
      ],
    });
    cdk.Tags.of(launchTemplate).add("Name", INSTANCE_NAME);

    if (useSpot) {
      // The fleet spreads the AZs so price-capacity-optimized picks one
      // with Spot capacity.
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
        spotOptions: {
          allocationStrategy: "price-capacity-optimized",
          instanceInterruptionBehavior: "terminate",
        },
        targetCapacitySpecification: {
          defaultTargetCapacityType: SPOT,
          onDemandTargetCapacity: 0,
          spotTargetCapacity: 1,
          totalTargetCapacity: 1,
        },
      });
      new cdk.CfnOutput(this, "FleetId", { value: fleet.attrFleetId });
    } else {
      // A fleet pins On-Demand to one AZ with no capacity check. A plain
      // launch with no subnet lets EC2 place it in an AZ that has capacity.
      const instance = new ec2.CfnInstance(this, "LlmInstance", {
        launchTemplate: {
          launchTemplateId: launchTemplate.launchTemplateId,
          version: launchTemplate.latestVersionNumber,
        },
      });
      new cdk.CfnOutput(this, "InstanceId", { value: instance.ref });
    }
  }
}
