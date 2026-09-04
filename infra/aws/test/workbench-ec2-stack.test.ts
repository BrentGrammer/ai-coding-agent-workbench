import assert from "node:assert/strict";
import * as cdk from "aws-cdk-lib/core";
import * as lambda from "aws-cdk-lib/aws-lambda";
import { Template } from "aws-cdk-lib/assertions";
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
  const tokenStack = new cdk.Stack(app, "Token", {
    env: { account, region },
  });
  const githubTokenFunction = new lambda.Function(tokenStack, "TokenFunction", {
    runtime: lambda.Runtime.NODEJS_24_X,
    handler: "index.handler",
    code: lambda.Code.fromInline("exports.handler = async () => ({})"),
  });
  const stack = new WorkbenchEc2Stack(app, "Workbench", {
    env: { account, region },
    githubTokenFunction,
  });
  return Template.fromStack(stack);
}

const ssmOnly = synthesize();
ssmOnly.resourceCountIs("AWS::EC2::SecurityGroupIngress", 0);

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
