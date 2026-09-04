export const TEST_ACCOUNT = "111111111111";
export const TEST_REGION = "us-west-2";

export function vpcLookupContext(
  options: { account?: string; region?: string; subnetCount?: number } = {},
): Record<string, unknown> {
  const account = options.account ?? TEST_ACCOUNT;
  const region = options.region ?? TEST_REGION;
  const subnetCount = options.subnetCount ?? 1;
  const contextKey =
    `vpc-provider:account=${account}:filter.isDefault=true:` +
    `region=${region}:returnAsymmetricSubnets=true`;
  return {
    [contextKey]: {
      vpcId: "vpc-00000000",
      vpcCidrBlock: "172.31.0.0/16",
      ownerAccountId: account,
      availabilityZones: [],
      subnetGroups: [
        {
          name: "Public",
          type: "Public",
          subnets: Array.from({ length: subnetCount }, (_, index) => ({
            subnetId: `subnet-0000000${String.fromCharCode(97 + index)}`,
            cidr: `172.31.${index}.0/24`,
            availabilityZone: `${region}${String.fromCharCode(97 + index)}`,
            routeTableId: `rtb-0000000${index}`,
          })),
        },
      ],
    },
  };
}
