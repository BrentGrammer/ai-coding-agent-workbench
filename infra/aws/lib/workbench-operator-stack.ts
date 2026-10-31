import * as cdk from "aws-cdk-lib/core";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";

const OPERATOR_POLICY_NAME = "agent-workbench-operator";
const WORKBENCH_INSTANCE_NAME = "agent-workbench-ec2";
const LLM_INSTANCE_NAME = "agent-workbench-gpu-llm";
const CDK_BOOTSTRAP_QUALIFIER = "hnb659fds";

// The IAM Identity Center permission set refers to this policy by name, so
// signing in through SSO only runs, updates, and deploys the workbench.
export class WorkbenchOperatorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const policy = new iam.ManagedPolicy(this, "OperatorPolicy", {
      managedPolicyName: OPERATOR_POLICY_NAME,
      description: "Runs, updates, and deploys the agent workbench.",
      statements: this.operatorStatements(),
    });

    new cdk.CfnOutput(this, "OperatorPolicyName", {
      value: policy.managedPolicyName,
    });
  }

  private operatorStatements(): iam.PolicyStatement[] {
    const instances = this.formatArn({
      service: "ec2",
      resource: "instance",
      resourceName: "*",
    });

    return [
      // EC2 has no way to scope Describe calls to some instances.
      new iam.PolicyStatement({
        actions: [
          "ec2:DescribeInstances",
          "ec2:GetSpotPlacementScores",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
        ],
        resources: ["*"],
      }),
      new iam.PolicyStatement({
        actions: ["ec2:StartInstances", "ec2:StopInstances"],
        resources: [instances],
        conditions: {
          StringEquals: { "aws:ResourceTag/Name": WORKBENCH_INSTANCE_NAME },
        },
      }),
      // SendCommand and StartSession check the instance and the document
      // separately, and documents carry no Name tag, so they get their own statement.
      new iam.PolicyStatement({
        actions: ["ssm:SendCommand", "ssm:StartSession"],
        resources: [instances],
        conditions: {
          StringEquals: {
            "ssm:resourceTag/Name": [WORKBENCH_INSTANCE_NAME, LLM_INSTANCE_NAME],
          },
        },
      }),
      new iam.PolicyStatement({
        actions: ["ssm:SendCommand"],
        resources: [
          this.formatArn({
            service: "ssm",
            account: "",
            resource: "document",
            resourceName: "AWS-RunShellScript",
          }),
        ],
      }),
      new iam.PolicyStatement({
        actions: ["ssm:StartSession"],
        resources: [
          this.formatArn({
            service: "ssm",
            resource: "document",
            resourceName: "SSM-SessionManagerRunShell",
          }),
        ],
      }),
      new iam.PolicyStatement({
        actions: ["ssm:ResumeSession", "ssm:TerminateSession"],
        resources: [
          this.formatArn({ service: "ssm", resource: "session", resourceName: "*" }),
        ],
      }),
      new iam.PolicyStatement({
        actions: ["cloudformation:DescribeStacks"],
        resources: [
          this.formatArn({
            service: "cloudformation",
            resource: "stack",
            resourceName: "AgentWorkbench*/*",
          }),
        ],
      }),
      // cdk deploy and destroy work through the roles that cdk bootstrap made.
      new iam.PolicyStatement({
        actions: ["sts:AssumeRole"],
        resources: [
          this.formatArn({
            service: "iam",
            region: "",
            resource: "role",
            resourceName: `cdk-${CDK_BOOTSTRAP_QUALIFIER}-*`,
          }),
        ],
      }),
    ];
  }
}
