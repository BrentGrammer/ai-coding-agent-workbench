import assert from "node:assert/strict";
import { test } from "node:test";
import * as cdk from "aws-cdk-lib/core";
import { Template } from "aws-cdk-lib/assertions";
import { WorkbenchOperatorStack } from "../lib/workbench-operator-stack.ts";

interface Statement {
  Effect: string;
  Action: string | string[];
  Resource: unknown;
  Condition?: Record<string, Record<string, unknown>>;
}

const app = new cdk.App();
const stack = new WorkbenchOperatorStack(app, "Operator", {
  env: { account: "111111111111", region: "us-west-2" },
});
const template = Template.fromStack(stack);
const [operatorPolicy] = Object.values(template.findResources("AWS::IAM::ManagedPolicy"));

function policyStatements(): Statement[] {
  return operatorPolicy.Properties.PolicyDocument.Statement as Statement[];
}

function actionsOf(statement: Statement): string[] {
  return [statement.Action].flat();
}

function statementsAllowing(action: string): Statement[] {
  return policyStatements().filter((statement) => actionsOf(statement).includes(action));
}

test("the SSO permission set can find the operator policy by its name", () => {
  assert.equal(operatorPolicy.Properties.ManagedPolicyName, "agent-workbench-operator");
});

test("no IAM users or access keys are created", () => {
  template.resourceCountIs("AWS::IAM::User", 0);
  template.resourceCountIs("AWS::IAM::AccessKey", 0);
});

test("only the workbench box can be started or stopped", () => {
  const [statement] = statementsAllowing("ec2:StartInstances");
  assert.deepEqual(actionsOf(statement), ["ec2:StartInstances", "ec2:StopInstances"]);
  assert.deepEqual(statement.Condition, {
    StringEquals: { "aws:ResourceTag/Name": "agent-workbench-ec2" },
  });
});

test("shell commands and sessions only reach the workbench and GPU boxes", () => {
  const instanceStatement = statementsAllowing("ssm:SendCommand").find(
    (statement) => statement.Condition,
  );
  assert.deepEqual(instanceStatement?.Condition, {
    StringEquals: {
      "ssm:resourceTag/Name": ["agent-workbench-ec2", "agent-workbench-gpu-llm"],
    },
  });
});

// A swapped Tailscale key would move the box onto someone else's tailnet.
test("the operator cannot change stored secrets such as the Tailscale keys", () => {
  assert.deepEqual(statementsAllowing("ssm:PutParameter"), []);
});

test("the operator cannot change IAM directly", () => {
  const iamActions = policyStatements()
    .flatMap(actionsOf)
    .filter((action) => action.startsWith("iam:"));
  assert.deepEqual(iamActions, []);
});
