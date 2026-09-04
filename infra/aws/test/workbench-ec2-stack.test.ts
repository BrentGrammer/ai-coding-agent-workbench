import assert from "node:assert/strict";
import * as path from "node:path";
import * as cdk from "aws-cdk-lib/core";
import { Match, Template } from "aws-cdk-lib/assertions";
import { BOX_FILES, boxFilesExclude } from "../lib/box-files";
import {
  ec2InstanceName,
  ec2StackId,
  parseDevelopers,
  SHARED_STACK_ID,
} from "../lib/developers";
import { addWorkbenchStacks } from "../lib/workbench-app";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack";
import { WorkbenchSharedStack } from "../lib/workbench-shared-stack";
import { TEST_ACCOUNT, TEST_REGION, vpcLookupContext } from "./vpc-context";

assert.deepEqual(parseDevelopers("Alice,bob", "unused"), ["alice", "bob"]);
assert.deepEqual(parseDevelopers(["Carol"], "unused"), ["carol"]);
assert.deepEqual(parseDevelopers(undefined, "m3mac"), ["m3mac"]);
assert.throws(
  () => parseDevelopers("alice_bob", "unused"),
  /Invalid developer name/,
);
assert.throws(
  () => parseDevelopers({ nope: true }, "unused"),
  /comma-separated string or an array/,
);

function appContext(
  extraContext: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    ...vpcLookupContext(),
    developers: "alice,bob",
    ...extraContext,
  };
}

function synthesizeApp(
  extraContext: Record<string, unknown> = {},
): cdk.App {
  const app = new cdk.App({ context: appContext(extraContext) });
  addWorkbenchStacks(app, { account: TEST_ACCOUNT, region: TEST_REGION });
  return app;
}

function stackTemplate(app: cdk.App, stackId: string): Template {
  const stack = app.node.findChild(stackId) as cdk.Stack;
  return Template.fromStack(stack);
}

interface PolicyStatement {
  Effect?: string;
  Action: string | string[];
  Resource: unknown;
  Condition?: Record<string, Record<string, unknown>>;
}

function policyStatementsFrom(
  policies: Array<{
    Properties: { PolicyDocument: { Statement: PolicyStatement[] } };
  }>,
): PolicyStatement[] {
  return policies.flatMap((policy) => policy.Properties.PolicyDocument.Statement);
}

function actionsOf(statement: PolicyStatement): string[] {
  return Array.isArray(statement.Action) ? statement.Action : [statement.Action];
}

function cidrIngressRules(template: Template): unknown[] {
  const standalone = Object.values(
    template.findResources("AWS::EC2::SecurityGroupIngress"),
  ).filter((resource) => {
    const properties = resource.Properties as {
      CidrIp?: string;
      CidrIpv6?: string;
    };
    return properties.CidrIp !== undefined || properties.CidrIpv6 !== undefined;
  });
  const inline = Object.values(
    template.findResources("AWS::EC2::SecurityGroup"),
  ).flatMap((resource) => {
    const rules = (resource.Properties.SecurityGroupIngress ?? []) as Array<{
      CidrIp?: string;
      CidrIpv6?: string;
    }>;
    return rules.filter(
      (rule) => rule.CidrIp !== undefined || rule.CidrIpv6 !== undefined,
    );
  });
  return [...standalone, ...inline];
}

function port22Rules(template: Template): unknown[] {
  const fromPort = (rule: { FromPort?: number; IpProtocol?: string }) =>
    rule.FromPort === 22 && rule.IpProtocol === "tcp";
  const standalone = Object.values(
    template.findResources("AWS::EC2::SecurityGroupIngress"),
  )
    .map((resource) => resource.Properties)
    .filter(fromPort);
  const inline = Object.values(
    template.findResources("AWS::EC2::SecurityGroup"),
  ).flatMap((resource) => {
    const rules = (resource.Properties.SecurityGroupIngress ?? []) as Array<{
      FromPort?: number;
      IpProtocol?: string;
    }>;
    return rules.filter(fromPort);
  });
  return [...standalone, ...inline];
}

function instanceRole(template: Template): {
  ManagedPolicyArns?: unknown[];
  Policies?: Array<{ PolicyDocument: { Statement: PolicyStatement[] } }>;
} {
  const roles = Object.values(template.findResources("AWS::IAM::Role")) as Array<{
    Properties: {
      AssumeRolePolicyDocument: {
        Statement: Array<{ Principal?: { Service?: string | string[] } }>;
      };
      ManagedPolicyArns?: unknown[];
      Policies?: Array<{ PolicyDocument: { Statement: PolicyStatement[] } }>;
    };
  }>;
  const match = roles.find((role) =>
    role.Properties.AssumeRolePolicyDocument.Statement.some((statement) => {
      const service = statement.Principal?.Service;
      const services = Array.isArray(service) ? service : [service];
      return services.includes("ec2.amazonaws.com");
    }),
  );
  assert.ok(match, "instance role is missing");
  return match.Properties;
}

const defaultApp = synthesizeApp();
const alice = stackTemplate(defaultApp, ec2StackId("alice"));
const bob = stackTemplate(defaultApp, ec2StackId("bob"));
const shared = stackTemplate(defaultApp, SHARED_STACK_ID);

const ec2StackIds = defaultApp.node.children
  .map((child) => child.node.id)
  .filter((id) => id.startsWith("AwsNativeWorkbenchEc2Stack-"))
  .sort();
assert.deepEqual(ec2StackIds, [
  "AwsNativeWorkbenchEc2Stack-alice",
  "AwsNativeWorkbenchEc2Stack-bob",
]);
assert.notEqual(ec2InstanceName("alice"), ec2InstanceName("bob"));

shared.resourceCountIs("AWS::EC2::InstanceConnectEndpoint", 1);
shared.hasResourceProperties("AWS::EC2::InstanceConnectEndpoint", {
  PreserveClientIp: false,
});
assert.equal(cidrIngressRules(shared).length, 0);

assert.equal(cidrIngressRules(alice).length, 0);
assert.equal(cidrIngressRules(bob).length, 0);
assert.equal(port22Rules(alice).length, 1);
assert.equal(port22Rules(bob).length, 1);
alice.hasResourceProperties("AWS::EC2::SecurityGroupIngress", {
  FromPort: 22,
  ToPort: 22,
  IpProtocol: "tcp",
  SourceSecurityGroupId: Match.anyValue(),
});

alice.hasResourceProperties("AWS::EC2::Instance", {
  Tags: Match.arrayWith([
    { Key: "Name", Value: ec2InstanceName("alice") },
    { Key: "SSMSessionRunAs", Value: "ubuntu" },
  ]),
});
bob.hasResourceProperties("AWS::EC2::Instance", {
  Tags: Match.arrayWith([{ Key: "Name", Value: ec2InstanceName("bob") }]),
});

const aliceRole = instanceRole(alice);
assert.match(
  JSON.stringify(aliceRole.ManagedPolicyArns ?? []),
  /AmazonSSMManagedInstanceCore/,
);
const extraManagedPolicies = (aliceRole.ManagedPolicyArns ?? []).filter(
  (arn) => !JSON.stringify(arn).includes("AmazonSSMManagedInstanceCore"),
);
assert.equal(extraManagedPolicies.length, 0);

const instanceInline = (aliceRole.Policies ?? []).flatMap(
  (policy) => policy.PolicyDocument.Statement,
);
const customerPolicies = Object.values(
  alice.findResources("AWS::IAM::Policy"),
) as Array<{
  Properties: {
    Roles?: unknown[];
    PolicyDocument: { Statement: PolicyStatement[] };
  };
}>;
const instanceAttached = policyStatementsFrom(
  customerPolicies.filter((policy) => (policy.Properties.Roles ?? []).length > 0),
);
const allInstanceStatements = [...instanceInline, ...instanceAttached];
const instanceStatements = allInstanceStatements.filter(
  (statement) => statement.Effect !== "Deny",
);
const instanceActions = new Set(instanceStatements.flatMap(actionsOf));
assert.ok(instanceActions.has("ec2:DescribeInstances"));
assert.ok([...instanceActions].some((action) => action.startsWith("s3:GetObject")));
for (const action of instanceActions) {
  assert.ok(
    action === "ec2:DescribeInstances" ||
      action.startsWith("s3:Get") ||
      action.startsWith("s3:List"),
    `instance role has unexpected action ${action}`,
  );
}

// The box may read only its own zip, never the whole assets bucket.
const s3Statements = instanceStatements.filter((statement) =>
  actionsOf(statement).some((action) => action.startsWith("s3:")),
);
assert.ok(s3Statements.length > 0);
for (const statement of s3Statements) {
  const resources = JSON.stringify(statement.Resource);
  assert.match(resources, /cdk-hnb659fds-assets/);
  assert.doesNotMatch(resources, /"\/\*"\]/, "instance role can read every asset");
  assert.match(resources, /\.zip/, "instance role s3 grant is not limited to the box zip");
}

const parameterDeny = allInstanceStatements.find(
  (statement) =>
    statement.Effect === "Deny" && actionsOf(statement).includes("ssm:GetParameter"),
);
assert.ok(parameterDeny, "instance role must not be able to read Parameter Store");
assert.ok(actionsOf(parameterDeny).includes("ssm:GetParametersByPath"));

const developerPolicies = Object.values(
  alice.findResources("AWS::IAM::ManagedPolicy"),
) as Array<{
  Properties: { PolicyDocument: { Statement: PolicyStatement[] } };
}>;
assert.equal(developerPolicies.length, 1);
const developerActions = new Set(
  policyStatementsFrom(developerPolicies).flatMap(actionsOf),
);
assert.ok(developerActions.has("ssm:StartSession"));
assert.ok(developerActions.has("ec2-instance-connect:OpenTunnel"));
assert.ok(developerActions.has("ec2:StartInstances"));
const startSession = policyStatementsFrom(developerPolicies).find(
  (statement) =>
    actionsOf(statement).includes("ssm:StartSession") &&
    statement.Condition?.StringEquals?.["ssm:resourceTag/Name"] ===
      ec2InstanceName("alice"),
);
assert.ok(startSession, "StartSession is not limited to this developer's instance");
const openTunnel = policyStatementsFrom(developerPolicies).find((statement) =>
  actionsOf(statement).includes("ec2-instance-connect:OpenTunnel"),
);
assert.ok(openTunnel);
assert.equal(
  Number(openTunnel.Condition?.NumericEquals?.["ec2-instance-connect:remotePort"]),
  22,
);

const templateJson = JSON.stringify(alice.toJSON());
assert.match(templateJson, /aws s3 cp/);
assert.doesNotMatch(templateJson, /git clone/);
assert.match(templateJson, /BoxFilesS3Url/);
alice.resourceCountIs("AWS::Lambda::Function", 0);

const repoRoot = path.join(__dirname, "..", "..", "..");
const ignore = cdk.IgnoreStrategy.glob(repoRoot, boxFilesExclude());
for (const file of BOX_FILES) {
  assert.equal(
    ignore.ignores(path.join(repoRoot, file)),
    false,
    `${file} must be in the box-files zip`,
  );
}
assert.equal(ignore.ignores(path.join(repoRoot, ".gitignore")), true);
assert.equal(ignore.ignores(path.join(repoRoot, ".env")), true);
assert.equal(ignore.ignores(path.join(repoRoot, "infra/aws/package.json")), true);
assert.equal(
  ignore.completelyIgnores(path.join(repoRoot, "infra/aws/node_modules")),
  true,
);

assert.throws(
  () => synthesizeApp({ sshCidr: "203.0.113.4/32" }),
  /sshCidr has been removed/,
);
assert.throws(
  () => synthesizeApp({ sshKeyName: "existing" }),
  /sshKeyName has been removed/,
);

const uploadedKeyApp = synthesizeApp({
  "sshPublicKey-alice": "ssh-ed25519 AAAATEST laptop",
});
stackTemplate(uploadedKeyApp, ec2StackId("alice")).hasResourceProperties(
  "AWS::EC2::KeyPair",
  { PublicKeyMaterial: "ssh-ed25519 AAAATEST laptop" },
);
stackTemplate(uploadedKeyApp, ec2StackId("bob")).resourceCountIs(
  "AWS::EC2::KeyPair",
  0,
);

const singleDev = new cdk.App({
  context: { ...vpcLookupContext(), developers: "alice", sshPublicKey: "ssh-ed25519 AAAASHARED" },
});
addWorkbenchStacks(singleDev, { account: TEST_ACCOUNT, region: TEST_REGION });
stackTemplate(singleDev, ec2StackId("alice")).hasResourceProperties(
  "AWS::EC2::KeyPair",
  { PublicKeyMaterial: "ssh-ed25519 AAAASHARED" },
);

function synthesizeIsolated(extraContext: Record<string, unknown> = {}): Template {
  const app = new cdk.App({ context: appContext(extraContext) });
  const sharedStack = new WorkbenchSharedStack(app, "Shared", {
    env: { account: TEST_ACCOUNT, region: TEST_REGION },
  });
  const stack = new WorkbenchEc2Stack(app, "Workbench", {
    env: { account: TEST_ACCOUNT, region: TEST_REGION },
    developer: "alice",
    instanceConnectEndpointArn: sharedStack.endpointArn,
    instanceConnectEndpointSecurityGroup: sharedStack.endpointSecurityGroup,
  });
  return Template.fromStack(stack);
}

synthesizeIsolated().hasResourceProperties("AWS::EC2::Instance", {
  Tags: Match.arrayWith([{ Key: "Name", Value: ec2InstanceName("alice") }]),
});

console.log(
  "each developer gets their own box and access policy, with no internet SSH and a tight instance role",
);
