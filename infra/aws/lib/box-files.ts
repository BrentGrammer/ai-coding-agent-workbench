import * as path from "node:path";
import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3assets from "aws-cdk-lib/aws-s3-assets";
import { Construct } from "constructs";

/**
 * Setup scripts for harness and dev box which are copied to s3.
 */

const REPO_ROOT = path.join(__dirname, "..", "..", "..");

// Only the files the boxes run. The zip must not include node_modules,
// cdk.out, or laptop-only agent tooling.
export const BOX_FILES = [
  "infra/aws/ec2/setup-workbench.sh",
  "infra/aws/ec2/agent-workbench-profile.sh",
  "infra/aws/ec2/login-welcome",
  "infra/aws/ec2/workbench-idle-stop",
  "infra/aws/ec2/clone-repo",
  "infra/aws/ec2/workbench-idle-stop.service",
  "infra/aws/ec2/workbench-idle-stop.timer",
  "infra/aws/ec2/tinyproxy.conf",
  "infra/aws/ec2/agent-egress-allowlist.txt",
  "infra/aws/ec2/nftables.conf",
  "bin/start-pi",
  "tools/agents/start_pi.sh",
  "tools/agents/local_llm.sh",
  "infra/aws/ec2/setup-llm.sh",
  "infra/aws/ec2/llm-idle-stop",
  "infra/aws/ec2/llm-idle-stop.service",
  "infra/aws/ec2/llm-idle-stop.timer",
  "tools/llm/ollama_inference_proxy.py",
];

export function boxFilesExclude(): string[] {
  const directories = new Set<string>();
  for (const file of BOX_FILES) {
    const parts = file.split("/");
    for (let i = 1; i < parts.length; i++) {
      directories.add(parts.slice(0, i).join("/"));
    }
  }
  return [
    // `**` does not match dotfiles, so name them or they land in the zip.
    ".*",
    "**/.*",
    "**",
    ...[...directories].sort().map((directory) => `!${directory}`),
    ...BOX_FILES.map((file) => `!${file}`),
  ];
}

export function boxFilesAsset(scope: Construct): s3assets.Asset {
  return new s3assets.Asset(scope, "BoxFiles", {
    path: REPO_ROOT,
    exclude: boxFilesExclude(),
    ignoreMode: cdk.IgnoreMode.GLOB,
  });
}

// Asset.grantRead would allow every asset in the bootstrap bucket. The box
// only needs its own zip.
export function grantBoxFilesRead(asset: s3assets.Asset, role: iam.IRole): void {
  asset.bucket.grantRead(role, asset.s3ObjectKey);
}

// AmazonSSMManagedInstanceCore includes ssm:GetParameter* on every parameter,
// which would expose the other workbench's secrets to anything on the box.
export function denyParameterStoreReads(): iam.PolicyStatement {
  return new iam.PolicyStatement({
    effect: iam.Effect.DENY,
    actions: [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
      "ssm:DescribeParameters",
    ],
    resources: ["*"],
  });
}

export function addBoxFilesInstall(
  userData: ec2.UserData,
  asset: s3assets.Asset,
): void {
  userData.addCommands(
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update",
    "apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip",
    "if ! command -v aws >/dev/null 2>&1; then",
    '  aws_arch="$(uname -m)"',
    '  case "$aws_arch" in',
    "    aarch64|arm64) aws_arch=aarch64 ;;",
    "    *) aws_arch=x86_64 ;;",
    "  esac",
    '  aws_tmp="$(mktemp -d)"',
    '  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$aws_tmp/awscli.zip"',
    '  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip.sig" -o "$aws_tmp/awscli.zip.sig"',
    "  gpg --import <<'GPGKEY'",
    "-----BEGIN PGP PUBLIC KEY BLOCK-----",
    "",
    "mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG",
    "ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx",
    "PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G",
    "TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz",
    "gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk",
    "C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG",
    "94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO",
    "lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG",
    "fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG",
    "EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX",
    "XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB",
    "tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF",
    "CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC",
    "akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM",
    "i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ",
    "hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA",
    "Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo",
    "h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC",
    "AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08",
    "Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9",
    "U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2",
    "b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO",
    "c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv",
    "2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz",
    "E91G7bb0hOb/cA==",
    "=knv7",
    "-----END PGP PUBLIC KEY BLOCK-----",
    "GPGKEY",
    '  gpg --verify "$aws_tmp/awscli.zip.sig" "$aws_tmp/awscli.zip"',
    '  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"',
    '  "$aws_tmp/aws/install"',
    '  rm -rf "$aws_tmp"',
    "fi",
  );
  const localZip = userData.addS3DownloadCommand({
    bucket: asset.bucket,
    bucketKey: asset.s3ObjectKey,
    localFile: "/tmp/agent-workbench.zip",
  });
  userData.addCommands(
    "rm -rf /opt/agent-workbench",
    "mkdir -p /opt/agent-workbench",
    `unzip -o '${localZip}' -d /opt/agent-workbench`,
    "chown -R root:root /opt/agent-workbench",
  );
}
