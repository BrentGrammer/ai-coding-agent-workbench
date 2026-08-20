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
    Overrides?: Array<{ SubnetId: string }>;
  }>;
}

function synthesize(extraContext: Record<string, unknown> = {}): Template {
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
    ...extraContext,
  };

  const app = new cdk.App({ context });
  const cacheStack = new cdk.Stack(app, "Cache", {
    env: { account, region },
  });
  const cacheBucket = new s3.Bucket(cacheStack, "CacheBucket");
  const stack = new WorkbenchLlmStack(app, "Llm", {
    env: { account, region },
    cacheBucket,
  });
  return Template.fromStack(stack);
}

function fleetProperties(template: Template): FleetProperties {
  template.resourceCountIs("AWS::EC2::Instance", 0);
  template.resourceCountIs("AWS::EC2::EC2Fleet", 1);
  const fleets = template.findResources("AWS::EC2::EC2Fleet");
  return Object.values(fleets)[0].Properties as FleetProperties;
}

function launchTemplateData(template: Template): {
  InstanceType: string;
  UserData: unknown;
} {
  const launchTemplates = template.findResources("AWS::EC2::LaunchTemplate");
  return Object.values(launchTemplates)[0].Properties.LaunchTemplateData;
}

const defaultTemplate = synthesize();
const spotFleet = fleetProperties(defaultTemplate);

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
  spotFleet.LaunchTemplateConfigs[0].Overrides?.map(({ SubnetId }) =>
    SubnetId
  ).sort(),
  [...subnetIds].sort(),
);

// On-Demand launches a plain instance with no fleet, subnet, or AZ, so EC2
// places it in an AZ that has capacity.
const onDemandTemplate = synthesize({ llmPurchaseOption: "on-demand" });
onDemandTemplate.resourceCountIs("AWS::EC2::EC2Fleet", 0);
onDemandTemplate.resourceCountIs("AWS::EC2::Instance", 1);
const onDemandInstance = Object.values(
  onDemandTemplate.findResources("AWS::EC2::Instance"),
)[0].Properties;
assert.ok(onDemandInstance.LaunchTemplate.LaunchTemplateId);
assert.equal(onDemandInstance.SubnetId, undefined);
assert.equal(onDemandInstance.AvailabilityZone, undefined);
// workbench llm status finds the box by this tag, which the launch
// template must carry because the instance resource sets none.
assert.match(
  JSON.stringify(launchTemplateData(onDemandTemplate)),
  /agent-workbench-gpu-llm/,
);

assert.throws(
  () => synthesize({ llmPurchaseOption: "reserved" }),
  /llmPurchaseOption must be "spot" or "on-demand"/,
);

const defaultLaunch = launchTemplateData(defaultTemplate);
assert.equal(defaultLaunch.InstanceType, "g6e.xlarge");
assert.match(
  JSON.stringify(defaultLaunch.UserData),
  /OLLAMA_CONTEXT_LENGTH=%s/,
);
assert.match(JSON.stringify(defaultLaunch.UserData), /'131072'/);

const overriddenLaunch = launchTemplateData(synthesize({
  llmInstanceType: "g6.xlarge",
  llmContextLength: "32768",
}));
assert.equal(overriddenLaunch.InstanceType, "g6.xlarge");
assert.match(JSON.stringify(overriddenLaunch.UserData), /'32768'/);

assert.throws(
  () => synthesize({ llmContextLength: "large" }),
  /llmContextLength must be a positive integer/,
);

assert.match(
  JSON.stringify(defaultLaunch.UserData),
  /OLLAMA_KV_CACHE_TYPE=%s/,
);
assert.match(JSON.stringify(defaultLaunch.UserData), /'q8_0'/);
const f16Launch = launchTemplateData(synthesize({ llmKvCacheType: "f16" }));
assert.match(JSON.stringify(f16Launch.UserData), /'f16'/);
assert.throws(
  () => synthesize({ llmKvCacheType: "fp8" }),
  /llmKvCacheType must be "q8_0" or "f16"/,
);

console.log(
  "workbench LLM stack supports Spot and On-Demand capacity, and a " +
    "configurable instance type, context length, and KV cache type",
);
