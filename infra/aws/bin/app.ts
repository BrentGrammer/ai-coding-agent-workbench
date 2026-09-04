#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack";
import { WorkbenchLlmCacheStack } from "../lib/workbench-llm-cache-stack";
import { WorkbenchLlmStack } from "../lib/workbench-llm-stack";

const app = new cdk.App();

cdk.Tags.of(app).add("app", "aws-native-agent-workbench");

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

const workbenchStack = new WorkbenchEc2Stack(app, "AwsNativeWorkbenchEc2Stack", {
  env,
  description: "Persistent EC2 workbench instance for coding agents.",
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
  workbenchSecurityGroup: workbenchStack.securityGroup,
});
