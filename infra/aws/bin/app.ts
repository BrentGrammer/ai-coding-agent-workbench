#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack.ts";
import { WorkbenchLlmCacheStack } from "../lib/workbench-llm-cache-stack.ts";
import { WorkbenchLlmStack } from "../lib/workbench-llm-stack.ts";
import { WorkbenchOperatorStack } from "../lib/workbench-operator-stack.ts";
import { WorkbenchTokenStack } from "../lib/workbench-token-stack.ts";

const app = new cdk.App();

cdk.Tags.of(app).add("app", "agent-workbench");

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

const tokenStack = new WorkbenchTokenStack(app, "AgentWorkbenchTokenStack", {
  env,
  description: "GitHub App token Lambda for the coding-agent workbench.",
});
new WorkbenchEc2Stack(app, "AgentWorkbenchEc2Stack", {
  env,
  description: "Persistent EC2 workbench instance for coding agents.",
  githubTokenFunction: tokenStack.githubTokenFunction,
});

const llmCacheStack = new WorkbenchLlmCacheStack(
  app,
  "AgentWorkbenchLlmCacheStack",
  {
    env,
    description: "S3 cache for workbench local-LLM model weights.",
  },
);

new WorkbenchLlmStack(app, "AgentWorkbenchLlmStack", {
  env,
  description: "GPU instance that serves workbench local LLMs.",
  cacheBucket: llmCacheStack.bucket,
});

new WorkbenchOperatorStack(app, "AgentWorkbenchOperatorStack", {
  env,
  description: "Limited IAM user and role for operating the workbench.",
});
