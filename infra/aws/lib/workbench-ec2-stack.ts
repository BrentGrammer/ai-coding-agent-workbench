import * as cdk from "aws-cdk-lib/core";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cloudwatchActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";
import { addBoxFilesInstall, boxFilesAsset } from "./box-files";
import { LLM_MODEL } from "./workbench-llm-stack";

// Resizing is this one line plus a stop/start.
const INSTANCE_TYPE = "t4g.large";
const DISK_GIB = 30;
const INSTANCE_NAME = "aws-native-agent-workbench-ec2";
const UBUNTU_2404_ARM64_AMI_PARAMETER =
  "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id";

export class WorkbenchEc2Stack extends cdk.Stack {
  public readonly securityGroup: ec2.ISecurityGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const sshCidr = this.node.tryGetContext("sshCidr") as string | undefined;
    const sshKeyName = this.node.tryGetContext("sshKeyName") as
      | string
      | undefined;
    const sshPublicKey = this.node.tryGetContext("sshPublicKey") as
      | string
      | undefined;

    if (sshCidr && !sshKeyName && !sshPublicKey) {
      throw new Error("sshCidr requires sshKeyName or sshPublicKey");
    }
    if (sshKeyName && sshPublicKey) {
      throw new Error("Set only one of sshKeyName or sshPublicKey");
    }

    const vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", { isDefault: true });

    const securityGroup = new ec2.SecurityGroup(this, "WorkbenchSecurityGroup", {
      vpc,
      description: "Agent workbench. SSM by default; optional CIDR-locked SSH.",
      allowAllOutbound: true,
    });
    this.securityGroup = securityGroup;
    if (sshCidr) {
      securityGroup.addIngressRule(
        ec2.Peer.ipv4(sshCidr),
        ec2.Port.tcp(22),
        "SSH from the configured client CIDR",
      );
    }

    const role = new iam.Role(this, "WorkbenchInstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      description:
        "Lets the workbench instance use SSM and read the box-files asset.",
    });
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
    );
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: ["ec2:DescribeInstances"],
        resources: ["*"],
      }),
    );

    const asset = boxFilesAsset(this);
    asset.grantRead(role);

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      "set -euo pipefail",
      "hostnamectl set-hostname aws-native-workbench",
      "mkdir -p /etc/agent-workbench",
      // This truncates, so every key the box needs belongs here. The setup
      // script only tops up what is missing on an already-running box.
      `printf 'AWS_REGION=%s\\nLOCAL_LLM_MODEL=%s\\nWORKBENCH_INSTANCE=true\\n' '${this.region}' '${LLM_MODEL}' > /etc/agent-workbench/workbench.env`,
      "chmod 644 /etc/agent-workbench/workbench.env",
    );
    addBoxFilesInstall(userData, asset);
    userData.addCommands(
      "bash /opt/agent-workbench/infra/aws/ec2/setup-workbench.sh",
    );

    // IMDSv2 with hop limit 1 keeps Docker containers away from instance-role
    // credentials; requireImdsv2 can't set the hop limit, so use a launch template.
    const imdsLaunchTemplate = new ec2.CfnLaunchTemplate(
      this,
      "ImdsLaunchTemplate",
      {
        launchTemplateData: {
          metadataOptions: {
            httpTokens: "required",
            httpPutResponseHopLimit: 1,
          },
        },
      },
    );

    const instance = new ec2.Instance(this, "WorkbenchInstance", {
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      instanceType: new ec2.InstanceType(INSTANCE_TYPE),
      machineImage: ec2.MachineImage.fromSsmParameter(
        UBUNTU_2404_ARM64_AMI_PARAMETER,
        { os: ec2.OperatingSystemType.LINUX },
      ),
      role,
      securityGroup,
      userData,
      associatePublicIpAddress: true,
      // `shutdown` on the box stops the instance instead of terminating it.
      instanceInitiatedShutdownBehavior: ec2.InstanceInitiatedShutdownBehavior.STOP,
      blockDevices: [
        {
          deviceName: "/dev/sda1",
          volume: ec2.BlockDeviceVolume.ebs(DISK_GIB, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            // The disk dies with the instance. Work repos live elsewhere and
            // the setup script rebuilds everything else. No orphaned volumes.
            deleteOnTermination: true,
          }),
        },
      ],
    });
    instance.instance.launchTemplate = {
      launchTemplateId: imdsLaunchTemplate.ref,
      version: imdsLaunchTemplate.attrLatestVersionNumber,
    };

    let effectiveKeyName = sshKeyName;
    let generatedKey: ec2.CfnKeyPair | undefined;
    if (sshPublicKey) {
      generatedKey = new ec2.CfnKeyPair(this, "WorkbenchSshKey", {
        keyName: `${this.stackName}-ssh`,
        publicKeyMaterial: sshPublicKey,
      });
      effectiveKeyName = generatedKey.keyName;
    }
    if (effectiveKeyName) {
      const cfnInstance = instance.node.defaultChild as ec2.CfnInstance;
      cfnInstance.keyName = effectiveKeyName;
      if (generatedKey) {
        cfnInstance.addResourceDependency(generatedKey);
      }
    }
    cdk.Tags.of(instance).add("Name", INSTANCE_NAME);

    // Backstop in case the on-box idle-stop timer ever breaks.
    const idleAlarm = new cloudwatch.Alarm(this, "IdleStopBackstopAlarm", {
      alarmDescription:
        "Stops the workbench instance after six quiet hours. Backstop only; the on-box timer stops it in 15 minutes.",
      metric: new cloudwatch.Metric({
        namespace: "AWS/EC2",
        metricName: "CPUUtilization",
        dimensionsMap: { InstanceId: instance.instanceId },
        statistic: "Average",
        period: cdk.Duration.hours(1),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 6,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    idleAlarm.addAlarmAction(
      new cloudwatchActions.Ec2Action(cloudwatchActions.Ec2InstanceAction.STOP),
    );

    new cdk.CfnOutput(this, "InstanceId", { value: instance.instanceId });
    new cdk.CfnOutput(this, "WorkbenchSecurityGroupId", {
      value: securityGroup.securityGroupId,
    });
    new cdk.CfnOutput(this, "BoxFilesS3Url", { value: asset.s3ObjectUrl });
  }
}
