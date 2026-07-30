import * as cdk from "aws-cdk-lib/core";
import { DockerImageAsset, Platform } from "aws-cdk-lib/aws-ecr-assets";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as path from "node:path";
import { Construct } from "constructs";

const AGENT_RUNTIME_NAME = "agent_workbench";
const GITHUB_APP_ID_PARAMETER_NAME = "/coding-agent-workbench/github/app-id";
const GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME =
  "/coding-agent-workbench/github/private-key";
const IDLE_SESSION_TIMEOUT_SECONDS = 900;
const MAX_SESSION_LIFETIME_SECONDS = 28800;

export class WorkbenchRuntimeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const image = new DockerImageAsset(this, "WorkbenchImage", {
      directory: path.join(__dirname, "..", "..", ".."),
      file: "infra/aws/runtime/Dockerfile",
      platform: Platform.LINUX_ARM64,
    });

    const executionRole = new iam.Role(this, "WorkbenchExecutionRole", {
      assumedBy: new iam.ServicePrincipal("bedrock-agentcore.amazonaws.com", {
        conditions: {
          StringEquals: { "aws:SourceAccount": this.account },
          ArnLike: {
            "aws:SourceArn": this.formatArn({
              service: "bedrock-agentcore",
              resource: "*",
            }),
          },
        },
      }),
      description: "Runs Agent Workbench sessions.",
    });

    const githubTokenFunction = this.createGitHubTokenFunction();

    image.repository.grantPull(executionRole);
    this.grantLogging(executionRole);
    githubTokenFunction.grantInvoke(executionRole);
    this.grantWorkloadIdentity(executionRole);

    executionRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "PreventInfrastructureDeployments",
        effect: iam.Effect.DENY,
        actions: ["cloudformation:*"],
        resources: ["*"],
      }),
    );

    const runtime = new cdk.CfnResource(this, "WorkbenchRuntime", {
      type: "AWS::BedrockAgentCore::Runtime",
      properties: {
        AgentRuntimeName: AGENT_RUNTIME_NAME,
        Description: "Generic Herdr and Hunk coding-agent workbench.",
        AgentRuntimeArtifact: {
          ContainerConfiguration: {
            ContainerUri: image.imageUri,
          },
        },
        RoleArn: executionRole.roleArn,
        NetworkConfiguration: { NetworkMode: "PUBLIC" },
        ProtocolConfiguration: "HTTP",
        EnvironmentVariables: {
          AWS_REGION: this.region,
          GITHUB_APP_TOKEN_FUNCTION_NAME: githubTokenFunction.functionName,
        },
        FilesystemConfigurations: [
          {
            SessionStorage: {
              MountPath: "/mnt/workspace",
            },
          },
        ],
        LifecycleConfiguration: {
          IdleRuntimeSessionTimeout: IDLE_SESSION_TIMEOUT_SECONDS,
          MaxLifetime: MAX_SESSION_LIFETIME_SECONDS,
        },
      },
    });

    runtime.node.addDependency(executionRole);

    const runtimeArn = runtime.getAtt("AgentRuntimeArn").toString();
    const callerPolicy = new iam.ManagedPolicy(this, "WorkbenchCallerPolicy", {
      description: "Allows trusted operators to use Agent Workbench.",
      statements: [
        new iam.PolicyStatement({
          actions: [
            "bedrock-agentcore:InvokeAgentRuntime",
            "bedrock-agentcore:InvokeAgentRuntimeCommand",
            "bedrock-agentcore:InvokeAgentRuntimeCommandShell",
            "bedrock-agentcore:ListAgentRuntimeCommandShells",
            "bedrock-agentcore:StopAgentRuntimeCommandShell",
            "bedrock-agentcore:StopRuntimeSession",
          ],
          resources: [
            runtimeArn,
            this.formatArn({
              service: "bedrock-agentcore",
              resource: "runtime",
              resourceName: `${AGENT_RUNTIME_NAME}-*/runtime-endpoint/*`,
            }),
          ],
        }),
        new iam.PolicyStatement({
          actions: ["logs:DescribeLogGroups"],
          resources: ["*"],
        }),
        new iam.PolicyStatement({
          actions: ["logs:PutRetentionPolicy"],
          resources: [
            this.formatArn({
              arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
              service: "logs",
              resource: "log-group",
              resourceName:
                "/aws/bedrock-agentcore/runtimes/agent_workbench-*",
            }),
          ],
        }),
      ],
    });

    new cdk.CfnOutput(this, "AgentRuntimeArn", { value: runtimeArn });
    new cdk.CfnOutput(this, "AgentRuntimeName", {
      value: AGENT_RUNTIME_NAME,
    });
    new cdk.CfnOutput(this, "AgentCoreImageUri", {
      value: image.imageUri,
    });
    new cdk.CfnOutput(this, "AgentCoreShellCallerPolicyArn", {
      value: callerPolicy.managedPolicyArn,
    });
    new cdk.CfnOutput(this, "GitHubAppTokenFunctionName", {
      value: githubTokenFunction.functionName,
    });
  }

  private grantLogging(role: iam.Role): void {
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ],
        resources: [
          this.formatArn({
            arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
            service: "logs",
            resource: "log-group",
            resourceName: "/aws/bedrock-agentcore/*",
          }),
          this.formatArn({
            arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
            service: "logs",
            resource: "log-group",
            resourceName: "/aws/bedrock-agentcore/*:*",
          }),
        ],
      }),
    );
  }

  // Holds the GitHub App private key so the agent container never can. The
  // container may only invoke this function, which hands back a token that
  // GitHub expires in an hour and scopes to one repository.
  private createGitHubTokenFunction(): lambda.Function {
    const tokenFunction = new lambda.Function(this, "GitHubAppTokenFunction", {
      runtime: lambda.Runtime.NODEJS_22_X,
      handler: "index.handler",
      code: lambda.Code.fromAsset(
        path.join(__dirname, "..", "lambda", "github-app-token"),
      ),
      timeout: cdk.Duration.seconds(15),
      memorySize: 256,
      description:
        "Makes short-lived GitHub App installation tokens for Agent Workbench.",
      environment: {
        GITHUB_APP_ID_PARAMETER_NAME,
        GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME,
      },
    });

    const parameterArns = [
      GITHUB_APP_ID_PARAMETER_NAME,
      GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME,
    ].map((parameterName) =>
      this.formatArn({
        service: "ssm",
        resource: "parameter",
        resourceName: parameterName.replace(/^\//, ""),
      }),
    );

    tokenFunction.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["ssm:GetParameter"],
        resources: parameterArns,
      }),
    );

    // The key that encrypts the parameters is not known when this synthesises,
    // so the encryption context pins decryption to those two parameters.
    tokenFunction.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["kms:Decrypt"],
        conditions: {
          StringEquals: {
            "kms:ViaService": `ssm.${this.region}.amazonaws.com`,
            "kms:EncryptionContext:PARAMETER_ARN": parameterArns,
          },
        },
        resources: ["*"],
      }),
    );

    return tokenFunction;
  }

  private grantWorkloadIdentity(role: iam.Role): void {
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId",
        ],
        resources: [
          this.formatArn({
            service: "bedrock-agentcore",
            resource: "workload-identity-directory",
            resourceName: "default",
          }),
          this.formatArn({
            service: "bedrock-agentcore",
            resource: "workload-identity-directory",
            resourceName: `default/workload-identity/${AGENT_RUNTIME_NAME}-*`,
          }),
        ],
      }),
    );
  }
}
