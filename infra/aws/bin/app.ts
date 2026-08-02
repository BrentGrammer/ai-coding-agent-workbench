#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack";
import { WorkbenchTokenStack } from "../lib/workbench-token-stack";

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
