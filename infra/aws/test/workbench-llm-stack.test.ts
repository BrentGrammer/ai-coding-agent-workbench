import assert from "node:assert/strict";
import * as cdk from "aws-cdk-lib/core";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Template } from "aws-cdk-lib/assertions";
import { WorkbenchLlmStack } from "../lib/workbench-llm-stack";

const account = "111111111111";
const region = "us-west-2";
const subnetIds = [
  "subnet-0000000a",
  "subnet-0000000b",
  "subnet-0000000c",
  "subnet-0000000d",
];
const contextKey =
  `vpc-provider:account=${account}:filter.isDefault=true:` +
  `region=${region}:returnAsymmetricSubnets=true`;

interface FleetProperties {
  Type: string;
  SpotOptions?: { AllocationStrategy: string };
  TargetCapacitySpecification: {
    DefaultTargetCapacityType: string;
    OnDemandTargetCapacity: number;
    SpotTargetCapacity: number;
    TotalTargetCapacity: number;
  };
  LaunchTemplateConfigs: Array<{
    Overrides: Array<{ SubnetId: string }>;
  }>;
}

function synthesizeFleet(purchaseOption?: string): FleetProperties {
  const context: Record<string, unknown> = {
    [contextKey]: {
      vpcId: "vpc-00000000",
      vpcCidrBlock: "172.31.0.0/16",
      ownerAccountId: account,
      availabilityZones: [],
      subnetGroups: [
        {
          name: "Public",
          type: "Public",
          subnets: subnetIds.map((subnetId, index) => ({
            subnetId,
            cidr: `172.31.${index}.0/24`,
            availabilityZone: `${region}${String.fromCharCode(97 + index)}`,
            routeTableId: `rtb-0000000${index}`,
          })),
        },
      ],
    },
  };
  if (purchaseOption) context.llmPurchaseOption = purchaseOption;

  const app = new cdk.App({ context });
  const cacheStack = new cdk.Stack(app, "Cache", {
    env: { account, region },
  });
  const cacheBucket = new s3.Bucket(cacheStack, "CacheBucket");
  const stack = new WorkbenchLlmStack(app, "Llm", {
    env: { account, region },
    cacheBucket,
  });
  const template = Template.fromStack(stack);

  template.resourceCountIs("AWS::EC2::Instance", 0);
  template.resourceCountIs("AWS::EC2::EC2Fleet", 1);

  const fleets = template.findResources("AWS::EC2::EC2Fleet");
  return Object.values(fleets)[0].Properties as FleetProperties;
}

const spotFleet = synthesizeFleet();

assert.equal(spotFleet.Type, "instant");
assert.equal(
  spotFleet.SpotOptions?.AllocationStrategy,
  "price-capacity-optimized",
);
assert.deepEqual(spotFleet.TargetCapacitySpecification, {
  DefaultTargetCapacityType: "spot",
  OnDemandTargetCapacity: 0,
  SpotTargetCapacity: 1,
  TotalTargetCapacity: 1,
});
assert.deepEqual(
  spotFleet.LaunchTemplateConfigs[0].Overrides.map(({ SubnetId }) =>
    SubnetId
  ).sort(),
  [...subnetIds].sort(),
);

const onDemandFleet = synthesizeFleet("on-demand");
assert.equal(onDemandFleet.SpotOptions, undefined);
assert.deepEqual(onDemandFleet.TargetCapacitySpecification, {
  DefaultTargetCapacityType: "on-demand",
  OnDemandTargetCapacity: 1,
  SpotTargetCapacity: 0,
  TotalTargetCapacity: 1,
});

assert.throws(
  () => synthesizeFleet("reserved"),
  /llmPurchaseOption must be "spot" or "on-demand"/,
);

console.log("workbench LLM stack supports Spot and On-Demand capacity");
