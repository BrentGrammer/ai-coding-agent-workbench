#!/usr/bin/env bash

# Installs the requested AWS CLI version for the current CPU architecture.
# Verifies AWS's signature and checks the ZIP before installing it.
# AWS public key source: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# Expected fingerprint: FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C

set -euo pipefail

AWS_CLI_ARCH="$(uname -m)"
AWS_CLI_PUBLIC_KEY=/tmp/aws-cli-public-key.asc
AWS_CLI_SIGNATURE=/tmp/awscliv2.sig
AWS_CLI_VERSION="${1:?AWS CLI version is required.}"
AWS_CLI_ZIP=/tmp/awscliv2.zip
GNUPGHOME=/tmp/aws-cli-gnupg

case "$AWS_CLI_ARCH" in
  x86_64)
    ;;
  aarch64 | arm64)
    AWS_CLI_ARCH=aarch64
    ;;
  *)
    echo "Unsupported AWS CLI architecture: $AWS_CLI_ARCH" >&2
    exit 1
    ;;
esac

AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}-${AWS_CLI_VERSION}.zip"
export GNUPGHOME

mkdir -m 700 "$GNUPGHOME"
gpg --batch --import "$AWS_CLI_PUBLIC_KEY"

curl -fsSL --retry 3 --retry-all-errors "$AWS_CLI_URL" -o "$AWS_CLI_ZIP"
curl -fsSL --retry 3 --retry-all-errors "${AWS_CLI_URL}.sig" -o "$AWS_CLI_SIGNATURE"
gpg --batch --verify "$AWS_CLI_SIGNATURE" "$AWS_CLI_ZIP"
unzip -tq "$AWS_CLI_ZIP"
unzip -q "$AWS_CLI_ZIP" -d /tmp
/tmp/aws/install

rm -rf \
  /tmp/aws \
  "$GNUPGHOME" \
  "$AWS_CLI_SIGNATURE" \
  "$AWS_CLI_ZIP"
