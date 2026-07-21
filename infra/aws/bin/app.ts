#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { WorkbenchRuntimeStack } from "../lib/workbench-runtime-stack";

const app = new cdk.App();

cdk.Tags.of(app).add("app", "agent-workbench");

new WorkbenchRuntimeStack(app, "AgentWorkbenchStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: "Generic coding-agent workbench on Bedrock AgentCore Runtime.",
});
