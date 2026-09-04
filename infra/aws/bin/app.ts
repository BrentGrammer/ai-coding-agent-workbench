#!/usr/bin/env node
import * as cdk from "aws-cdk-lib/core";
import { addWorkbenchStacks } from "../lib/workbench-app";

const app = new cdk.App();

cdk.Tags.of(app).add("app", "aws-native-agent-workbench");

addWorkbenchStacks(app, {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
});
