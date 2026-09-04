import * as path from "node:path";
import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
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
  "infra/aws/ec2/workbench-idle-stop.service",
  "infra/aws/ec2/workbench-idle-stop.timer",
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

export function addBoxFilesInstall(
  userData: ec2.UserData,
  asset: s3assets.Asset,
): void {
  userData.addCommands(
    "export DEBIAN_FRONTEND=noninteractive",
    "apt-get update",
    "apt-get install -y --no-install-recommends ca-certificates curl unzip",
    "if ! command -v aws >/dev/null 2>&1; then",
    '  aws_arch="$(uname -m)"',
    '  case "$aws_arch" in',
    "    aarch64|arm64) aws_arch=aarch64 ;;",
    "    *) aws_arch=x86_64 ;;",
    "  esac",
    '  aws_tmp="$(mktemp -d)"',
    '  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$aws_tmp/awscli.zip"',
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
