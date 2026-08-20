import * as cdk from "aws-cdk-lib/core";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cloudwatchActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import { Construct } from "constructs";

// Resizing is this one line plus a stop/start.
const INSTANCE_TYPE = "t4g.large";
const DISK_GIB = 30;
const INSTANCE_NAME = "agent-workbench-ec2";
const TAILSCALE_AUTH_KEY_PARAMETER = "/coding-agent-workbench/tailscale/auth-key";
// Cloned to /opt/agent-workbench on first boot to run the setup script.
// Override with CDK context: -c repoUrl=https://github.com/you/fork.git
const DEFAULT_REPO_URL =
  "https://github.com/BrentGrammer/ai-coding-agent-workbench.git";
const UBUNTU_2404_ARM64_AMI_PARAMETER =
  "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id";

export interface WorkbenchEc2StackProps extends cdk.StackProps {
  githubTokenFunction: lambda.IFunction;
}

export class WorkbenchEc2Stack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WorkbenchEc2StackProps) {
    super(scope, id, props);

    const repoUrl =
      (this.node.tryGetContext("repoUrl") as string) ?? DEFAULT_REPO_URL;

    const vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", { isDefault: true });

    // Zero inbound rules. Tailscale and SSM both connect outbound.
    const securityGroup = new ec2.SecurityGroup(this, "WorkbenchSecurityGroup", {
      vpc,
      description: "Agent workbench. No inbound; Tailscale and SSM go outbound.",
      allowAllOutbound: true,
    });

    const role = new iam.Role(this, "WorkbenchInstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      description:
        "Lets the workbench instance use SSM and invoke the GitHub token function.",
    });
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
    );
    props.githubTokenFunction.grantInvoke(role);
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

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      "set -euo pipefail",
      "hostnamectl set-hostname agent-workbench",
      "mkdir -p /etc/agent-workbench",
      // This truncates, so every key the box needs belongs here. The setup
      // script only tops up what is missing on an already-running box.
      `printf 'AWS_REGION=%s\\nGITHUB_APP_TOKEN_FUNCTION_NAME=%s\\n' '${this.region}' '${props.githubTokenFunction.functionName}' > /etc/agent-workbench/workbench.env`,
      "chmod 644 /etc/agent-workbench/workbench.env",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get install -y git",
      // Root-owned machine config, not a working copy. The agent user runs as
      // ubuntu and must not be able to edit what the update command sudo-runs.
      `[ -d /opt/agent-workbench/.git ] || git clone --branch main ${repoUrl} /opt/agent-workbench`,
      "chown -R root:root /opt/agent-workbench",
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
            // The disk dies with the instance. Repos live on GitHub and the
            // setup script rebuilds everything else; a rebuild only costs
            // re-running the one-time setup. No orphaned volumes.
            deleteOnTermination: true,
          }),
        },
      ],
    });
    instance.instance.launchTemplate = {
      launchTemplateId: imdsLaunchTemplate.ref,
      version: imdsLaunchTemplate.attrLatestVersionNumber,
    };
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
  }
}
