import * as cdk from "aws-cdk-lib/core";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

export class WorkbenchLlmCacheStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.bucket = new s3.Bucket(this, "ModelCache", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      // One current copy of the model. Versioning would keep every old 17 GB refresh.
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      lifecycleRules: [
        {
          id: "abort-incomplete-multipart",
          // A failed 17 GB upload must not sit around billing.
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
        // To expire unused objects later, add:
        // {
        //   id: "expire-unused-model-cache",
        //   expiration: cdk.Duration.days(60),
        // },
      ],
    });

    new cdk.CfnOutput(this, "BucketName", { value: this.bucket.bucketName });
  }
}
