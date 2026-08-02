import * as cdk from "aws-cdk-lib/core";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as path from "node:path";
import { Construct } from "constructs";

const GITHUB_APP_ID_PARAMETER_NAME = "/coding-agent-workbench/github/app-id";
const GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME =
  "/coding-agent-workbench/github/private-key";

export class WorkbenchRuntimeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const githubTokenFunction = this.createGitHubTokenFunction();

    new cdk.CfnOutput(this, "GitHubAppTokenFunctionName", {
      value: githubTokenFunction.functionName,
    });
  }

  // Holds the GitHub App private key so the workbench host never can. The
  // host may only invoke this function, which hands back a token that
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
        ...(process.env.ALLOWED_REPOSITORIES
          ? { ALLOWED_REPOSITORIES: process.env.ALLOWED_REPOSITORIES }
          : {}),
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
}
