import assert from "node:assert/strict";
import * as path from "node:path";
import * as cdk from "aws-cdk-lib/core";
import { Template } from "aws-cdk-lib/assertions";
import { BOX_FILES, boxFilesExclude } from "../lib/box-files";
import { WorkbenchEc2Stack } from "../lib/workbench-ec2-stack";

const account = "111111111111";
const region = "us-west-2";
const contextKey =
  `vpc-provider:account=${account}:filter.isDefault=true:` +
  `region=${region}:returnAsymmetricSubnets=true`;

function synthesize(extraContext: Record<string, unknown> = {}): Template {
  const app = new cdk.App({
    context: {
      [contextKey]: {
        vpcId: "vpc-00000000",
        vpcCidrBlock: "172.31.0.0/16",
        ownerAccountId: account,
        availabilityZones: [],
        subnetGroups: [
          {
            name: "Public",
            type: "Public",
            subnets: [
              {
                subnetId: "subnet-0000000a",
                cidr: "172.31.0.0/24",
                availabilityZone: "us-west-2a",
                routeTableId: "rtb-00000000",
              },
            ],
          },
        ],
      },
      ...extraContext,
    },
  });
  const stack = new WorkbenchEc2Stack(app, "Workbench", {
    env: { account, region },
  });
  return Template.fromStack(stack);
}

interface PolicyStatement {
  Action: string | string[];
  Resource: unknown;
}

function policyStatements(template: Template): PolicyStatement[] {
  const policies = Object.values(
    template.findResources("AWS::IAM::Policy"),
  ) as Array<{
    Properties: { PolicyDocument: { Statement: PolicyStatement[] } };
  }>;
  const roles = Object.values(template.findResources("AWS::IAM::Role")) as Array<{
    Properties: {
      Policies?: Array<{ PolicyDocument: { Statement: PolicyStatement[] } }>;
    };
  }>;
  return [
    ...policies.flatMap((policy) => policy.Properties.PolicyDocument.Statement),
    ...roles.flatMap((role) =>
      (role.Properties.Policies ?? []).flatMap(
        (policy) => policy.PolicyDocument.Statement,
      ),
    ),
  ];
}

function actionsOf(statement: PolicyStatement): string[] {
  return Array.isArray(statement.Action) ? statement.Action : [statement.Action];
}

const ssmOnly = synthesize();
ssmOnly.resourceCountIs("AWS::EC2::SecurityGroupIngress", 0);
ssmOnly.resourceCountIs("AWS::Lambda::Function", 0);

const templateJson = JSON.stringify(ssmOnly.toJSON());
assert.match(templateJson, /aws s3 cp/);
assert.doesNotMatch(templateJson, /git clone/);
assert.match(templateJson, /BoxFilesS3Url/);

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

const s3Statements = policyStatements(ssmOnly).filter((statement) =>
  actionsOf(statement).some((action) => action.startsWith("s3:")),
);
assert.ok(
  s3Statements.some((statement) =>
    actionsOf(statement).some((action) => action.startsWith("s3:GetObject")),
  ),
);
for (const statement of s3Statements) {
  assert.notEqual(statement.Resource, "*");
  assert.match(JSON.stringify(statement.Resource), /cdk-hnb659fds-assets/);
}

assert.throws(
  () => synthesize({ sshCidr: "203.0.113.4/32" }),
  /sshCidr requires sshKeyName or sshPublicKey/,
);
assert.throws(
  () => synthesize({ sshKeyName: "existing", sshPublicKey: "ssh-ed25519 AAAA" }),
  /Set only one of sshKeyName or sshPublicKey/,
);

const existingKey = synthesize({
  sshCidr: "203.0.113.4/32",
  sshKeyName: "agent-workbench",
});
existingKey.hasResourceProperties("AWS::EC2::SecurityGroup", {
  SecurityGroupIngress: [
    {
      CidrIp: "203.0.113.4/32",
      FromPort: 22,
      IpProtocol: "tcp",
      ToPort: 22,
    },
  ],
});
existingKey.hasResourceProperties("AWS::EC2::Instance", {
  KeyName: "agent-workbench",
});

const uploadedKey = synthesize({
  sshCidr: "203.0.113.4/32",
  sshPublicKey: "ssh-ed25519 AAAATEST laptop",
});
uploadedKey.hasResourceProperties("AWS::EC2::KeyPair", {
  PublicKeyMaterial: "ssh-ed25519 AAAATEST laptop",
});

console.log("workbench access defaults to SSM and restricts optional SSH");
