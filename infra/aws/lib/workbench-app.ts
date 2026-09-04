import * as os from "node:os";
import * as cdk from "aws-cdk-lib/core";
import {
  ec2StackId,
  parseDevelopers,
  SHARED_STACK_ID,
  sshPublicKeyFor,
} from "./developers";
import { WorkbenchEc2Stack } from "./workbench-ec2-stack";
import { WorkbenchLlmCacheStack } from "./workbench-llm-cache-stack";
import { WorkbenchLlmStack } from "./workbench-llm-stack";
import { WorkbenchSharedStack } from "./workbench-shared-stack";

export function addWorkbenchStacks(app: cdk.App, env: cdk.Environment): void {
  const developers = parseDevelopers(
    app.node.tryGetContext("developers"),
    os.userInfo().username,
  );

  const sharedStack = new WorkbenchSharedStack(app, SHARED_STACK_ID, {
    env,
    description:
      "Shared EC2 Instance Connect Endpoint for AWS-native workbench SSH.",
  });

  const workbenchStacks = developers.map((developer) => {
    return new WorkbenchEc2Stack(app, ec2StackId(developer), {
      env,
      description: `Persistent EC2 workbench instance for ${developer}.`,
      developer,
      sshPublicKey: sshPublicKeyFor(
        app.node,
        developer,
        developers.length,
      ),
      instanceConnectEndpointArn: sharedStack.endpointArn,
      instanceConnectEndpointSecurityGroup: sharedStack.endpointSecurityGroup,
    });
  });

  const llmCacheStack = new WorkbenchLlmCacheStack(
    app,
    "AwsNativeWorkbenchLlmCacheStack",
    {
      env,
      description: "S3 cache for workbench local-LLM model weights.",
    },
  );

  new WorkbenchLlmStack(app, "AwsNativeWorkbenchLlmStack", {
    env,
    description: "GPU instance that serves workbench local LLMs.",
    cacheBucket: llmCacheStack.bucket,
    workbenchSecurityGroups: workbenchStacks.map((stack) => stack.securityGroup),
  });
}
