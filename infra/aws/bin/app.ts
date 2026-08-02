#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack";
import { WorkbenchRuntimeStack } from "../lib/workbench-runtime-stack";

const app = new cdk.App();

cdk.Tags.of(app).add("app", "agent-workbench");

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

const runtimeStack = new WorkbenchRuntimeStack(app, "AgentWorkbenchStack", {
  env,
  description: "GitHub App token Lambda for the coding-agent workbench.",
});

new WorkbenchEc2Stack(app, "AgentWorkbenchEc2Stack", {
  env,
  description: "Persistent EC2 workbench instance (issue #20 Phase 2).",
  githubTokenFunction: runtimeStack.githubTokenFunction,
});
