import * as cdk from "aws-cdk-lib/core";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";

const OPERATOR_NAME = "agent-workbench-operator";
const WORKBENCH_INSTANCE_NAME = "agent-workbench-ec2";
const LLM_INSTANCE_NAME = "agent-workbench-gpu-llm";
const CDK_BOOTSTRAP_QUALIFIER = "hnb659fds";

// A user whose access keys can do nothing alone. With an MFA code they can
// assume a role that only runs, updates, and deploys the workbench.
export class WorkbenchOperatorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const user = new iam.User(this, "OperatorUser", { userName: OPERATOR_NAME });

    const role = new iam.Role(this, "OperatorRole", {
      roleName: OPERATOR_NAME,
      description: "Runs, updates, and deploys the agent workbench.",
      assumedBy: new iam.ArnPrincipal(user.userArn).withConditions({
        Bool: { "aws:MultiFactorAuthPresent": "true" },
      }),
      maxSessionDuration: cdk.Duration.hours(1),
    });
    role.grantAssumeRole(user);

    for (const statement of this.operatorStatements()) {
      role.addToPolicy(statement);
    }

    new cdk.CfnOutput(this, "OperatorRoleArn", { value: role.roleArn });
    new cdk.CfnOutput(this, "OperatorUserName", { value: user.userName });
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
