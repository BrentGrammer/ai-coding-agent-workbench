import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { Construct } from "constructs";

export class WorkbenchSharedStack extends cdk.Stack {
  public readonly endpointSecurityGroup: ec2.ISecurityGroup;
  public readonly endpointArn: string;
  public readonly endpointId: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", { isDefault: true });
    const subnet = vpc.publicSubnets[0];
    if (!subnet) {
      throw new Error("The default VPC has no public subnet for the Instance Connect Endpoint");
    }

    const securityGroup = new ec2.SecurityGroup(this, "InstanceConnectEndpointSg", {
      vpc,
      description:
        "EC2 Instance Connect Endpoint. Laptop traffic uses the AWS API, not inbound ports.",
      allowAllOutbound: true,
    });
    this.endpointSecurityGroup = securityGroup;

    // preserveClientIp stays off so instance security groups can allow this
    // endpoint by security-group reference instead of a client CIDR.
    const endpoint = new ec2.CfnInstanceConnectEndpoint(
      this,
      "InstanceConnectEndpoint",
      {
        subnetId: subnet.subnetId,
        securityGroupIds: [securityGroup.securityGroupId],
        preserveClientIp: false,
        tags: [
          {
            key: "Name",
            value: "aws-native-agent-workbench-eice",
          },
        ],
      },
    );
    this.endpointId = endpoint.attrId;
    this.endpointArn = this.formatArn({
      service: "ec2",
      resource: "instance-connect-endpoint",
      resourceName: endpoint.attrId,
      arnFormat: cdk.ArnFormat.SLASH_RESOURCE_NAME,
    });

    new cdk.CfnOutput(this, "InstanceConnectEndpointId", {
      value: this.endpointId,
    });
  }
}
