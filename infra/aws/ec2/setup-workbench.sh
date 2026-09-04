#!/usr/bin/env bash
# Installs and updates everything on the EC2 workbench. Idempotent: cloud-init
# runs it on first boot, and `aws-workbench ec2 update` re-runs it for updates.
set -euo pipefail

# Pinned artifact versions and verification hashes.
NODE_VERSION="24.9.0"
NODE_SHA256_ARM64="dab232a90169737a48149149dd6707e7fdcbaefbaa94b4871047a38e93db947f"
NODE_SHA256_X64="d57d6c28a35785f58f33899a0aa0bfc83f7a8ef4448b6cf3f7d0961efc7b9189"

AWS_CLI_GPG_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"

PI_VERSION="0.84.4"

AGY_VERSION="1.1.26"
AGY_URL_ARM64="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.26-5550154686791680/linux-arm/cli_linux_arm64.tar.gz"
AGY_SHA512_ARM64="332dddb06ab4d901a44cfd4b9b358848230e64a64515a8e79b03822348adac9ce92d54cb4fc5119ef075edfba922820c926dfddf82d3a49f4ecdb6e6704dfc75"
AGY_URL_X64="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.26-5550154686791680/linux-x64/cli_linux_x64.tar.gz"
AGY_SHA512_X64="80f2e7bf1fe0833487975b320b07176b82dd2cc2043b8acb4201b37b86d604af50718400b58af0f41adc68b389640f6ff95362da87a9ef1682b34258e83110b2"

WORKBENCH_USER=ubuntu
AGENT_USER=agent
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root: sudo $0" >&2
  exit 1
fi

install -d -m 755 /etc/agent-workbench
touch /etc/agent-workbench/workbench.env
chmod 644 /etc/agent-workbench/workbench.env
sed -i '/^GITHUB_APP_TOKEN_FUNCTION_NAME=/d' /etc/agent-workbench/workbench.env
grep -q '^LOCAL_LLM_MODEL=' /etc/agent-workbench/workbench.env ||
  echo 'LOCAL_LLM_MODEL=qwen3.8:27b' >> /etc/agent-workbench/workbench.env
grep -q '^WORKBENCH_INSTANCE=' /etc/agent-workbench/workbench.env ||
  echo 'WORKBENCH_INSTANCE=true' >> /etc/agent-workbench/workbench.env

export DEBIAN_FRONTEND=noninteractive

echo "== System packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  less \
  ncurses-term \
  nftables \
  openssh-server \
  tinyproxy \
  unattended-upgrades \
  unzip

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "== Node $NODE_VERSION"
need_node=true
if command -v node >/dev/null 2>&1; then
  if [ "$(node --version 2>/dev/null || true)" = "v$NODE_VERSION" ]; then
    need_node=false
  fi
fi

if [ "$need_node" = true ]; then
  case "$(uname -m)" in
    aarch64|arm64)
      node_arch="arm64"
      node_sha="$NODE_SHA256_ARM64"
      ;;
    x86_64|amd64)
      node_arch="x64"
      node_sha="$NODE_SHA256_X64"
      ;;
    *)
      echo "ERROR: Unsupported architecture for Node: $(uname -m)" >&2
      exit 1
      ;;
  esac

  node_tmp="$(mktemp -d)"
  node_tarball="node-v${NODE_VERSION}-linux-${node_arch}.tar.gz"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${node_tarball}" -o "$node_tmp/$node_tarball"
  echo "$node_sha  $node_tmp/$node_tarball" | sha256sum -c -
  tar -xzf "$node_tmp/$node_tarball" -C /usr/local --strip-components=1
  rm -rf "$node_tmp"
fi
node --version
npm --version

echo "== AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  case "$(uname -m)" in
    aarch64|arm64) aws_arch="aarch64" ;;
    *) aws_arch="x86_64" ;;
  esac

  aws_tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$aws_tmp/awscli.zip"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip.sig" -o "$aws_tmp/awscli.zip.sig"

  gpg --import <<'GPGKEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM
i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ
hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA
Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo
h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC
AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08
Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9
U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2
b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO
c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv
2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz
E91G7bb0hOb/cA==
=knv7
-----END PGP PUBLIC KEY BLOCK-----
GPGKEY

  # A good signature from any key in the keyring is not enough. It must be this key.
  gpg --status-fd 1 --verify "$aws_tmp/awscli.zip.sig" "$aws_tmp/awscli.zip" |
    grep -q "^\[GNUPG:\] VALIDSIG $AWS_CLI_GPG_FINGERPRINT "
  unzip -q "$aws_tmp/awscli.zip" -d "$aws_tmp"
  "$aws_tmp/aws/install" --update
  rm -rf "$aws_tmp"
fi
aws --version

echo "== Users and workspace"
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -U "$AGENT_USER"
fi
passwd -l "$AGENT_USER" >/dev/null 2>&1 || true

# Group membership allows developer and agent to collaborate in the workspace.
usermod -a -G "$AGENT_USER" "$WORKBENCH_USER"
chmod 750 "/home/$AGENT_USER"
install -d -m 2775 -o "$AGENT_USER" -g "$AGENT_USER" "/home/$AGENT_USER/workspace"

ln -sfn "/home/$AGENT_USER/workspace" "/home/$WORKBENCH_USER/workspace"
chown -h "$WORKBENCH_USER:$WORKBENCH_USER" "/home/$WORKBENCH_USER/workspace"

echo "== Local egress proxy (tinyproxy)"
install -d -m 755 /etc/tinyproxy
install -m 644 "$REPO_DIR/infra/aws/ec2/agent-egress-allowlist.txt" /etc/tinyproxy/agent-egress-allowlist.txt
install -m 644 "$REPO_DIR/infra/aws/ec2/tinyproxy.conf" /etc/tinyproxy/tinyproxy.conf
systemctl daemon-reload
systemctl enable tinyproxy
systemctl restart tinyproxy

echo "== nftables firewall"
imds_token="$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
imds_get() {
  curl -fsS -H "X-aws-ec2-metadata-token: $imds_token" "http://169.254.169.254/latest/meta-data/$1"
}
mac="$(imds_get network/interfaces/macs/ | head -n1 | tr -d '/')"
vpc_cidr="$(imds_get "network/interfaces/macs/$mac/vpc-ipv4-cidr-block")"
if [[ ! "$vpc_cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
  echo "ERROR: Could not read the VPC CIDR from instance metadata: $vpc_cidr" >&2
  exit 1
fi
sed "s|@VPC_CIDR@|$vpc_cidr|" "$REPO_DIR/infra/aws/ec2/nftables.conf" > /etc/nftables.conf
chmod 644 /etc/nftables.conf
nft -f /etc/nftables.conf
systemctl enable nftables

echo "== sshd"
install -d -m 755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/50-workbench.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin no
AllowUsers ubuntu
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "== Workbench files"
install -d -m 755 /etc/agent-workbench

install -m 755 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop" /usr/local/bin/aws-workbench-idle-stop
install -m 755 "$REPO_DIR/infra/aws/ec2/clone-repo" /usr/local/bin/clone-repo
ln -sfn /opt/agent-workbench/bin/start-pi /usr/local/bin/start-pi

echo "== Keep the agent out of the developer's git internals"
# The agent edits source files. Only the developer may change hooks, config,
# and refs, or a poisoned hook would run with ubuntu's sudo.
install -d -m 755 /etc/agent-workbench/git-hooks-disabled
sudo -u "$WORKBENCH_USER" -H git config --global core.hooksPath /etc/agent-workbench/git-hooks-disabled
sudo -u "$WORKBENCH_USER" -H npm config set ignore-scripts true
for git_dir in "/home/$AGENT_USER/workspace"/*/.git; do
  [ -d "$git_dir" ] || continue
  if [ "$(stat -c %U "$git_dir")" = "$WORKBENCH_USER" ]; then
    chmod -R g-w "$git_dir"
  fi
done

install -m 644 "$REPO_DIR/infra/aws/ec2/agent-workbench-profile.sh" /etc/profile.d/agent-workbench.sh
install -m 644 "$REPO_DIR/infra/aws/ec2/login-welcome" /etc/agent-workbench/login-welcome

# Root owns /opt/agent-workbench so the agent cannot tamper with it.
chown -R root:root /opt/agent-workbench
chmod -R 755 /opt/agent-workbench

echo "== Remove leftover GitHub token chain"
systemctl disable --now github-token-relay.service 2>/dev/null || true
rm -f /etc/systemd/system/github-token-relay.service
rm -f /usr/local/bin/git-credential-github-app
rm -f /usr/local/lib/agent-workbench/github-token-relay.mjs \
  /usr/local/lib/agent-workbench/github-app-token-client.mjs \
  /usr/local/lib/agent-workbench/github-token-relay-service.mjs
helper="$(sudo -u "$WORKBENCH_USER" -H git config --global --get credential.helper 2>/dev/null || true)"
if [ "$helper" = "/usr/local/bin/git-credential-github-app" ]; then
  sudo -u "$WORKBENCH_USER" -H git config --global --unset-all credential.helper || true
  sudo -u "$WORKBENCH_USER" -H git config --global --unset-all credential.useHttpPath || true
fi

echo "== Swap"
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon -a

echo "== systemd units"
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.service" /etc/systemd/system/workbench-idle-stop.service
install -m 644 "$REPO_DIR/infra/aws/ec2/workbench-idle-stop.timer" /etc/systemd/system/workbench-idle-stop.timer
systemctl daemon-reload
systemctl enable workbench-idle-stop.timer
systemctl start workbench-idle-stop.timer

echo "== Agent CLIs for $AGENT_USER"
sudo -u "$AGENT_USER" -H \
  env PI_VERSION="$PI_VERSION" \
      AGY_VERSION="$AGY_VERSION" \
      AGY_URL_ARM64="$AGY_URL_ARM64" \
      AGY_SHA512_ARM64="$AGY_SHA512_ARM64" \
      AGY_URL_X64="$AGY_URL_X64" \
      AGY_SHA512_X64="$AGY_SHA512_X64" \
      HTTP_PROXY="http://127.0.0.1:8888" \
      HTTPS_PROXY="http://127.0.0.1:8888" \
      http_proxy="http://127.0.0.1:8888" \
      https_proxy="http://127.0.0.1:8888" \
  bash -s <<'USER_SETUP'
set -euo pipefail

export NPM_CONFIG_PREFIX="$HOME/.local/npm"
export PATH="$HOME/.local/npm/bin:$HOME/.local/bin:$PATH"
mkdir -p "$HOME/.local/npm" "$HOME/.local/bin" "$HOME/workspace"

# Skip lifecycle scripts on installs to prevent untrusted code execution.
npm config set prefix "$HOME/.local/npm"
npm config set ignore-scripts true
npm config set proxy "http://127.0.0.1:8888"
npm config set https-proxy "http://127.0.0.1:8888"

npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"
pi --version

need_agy=true
if command -v agy >/dev/null 2>&1; then
  if agy --version 2>&1 | grep -q "$AGY_VERSION"; then
    need_agy=false
  fi
fi

if [ "$need_agy" = true ]; then
  case "$(uname -m)" in
    aarch64|arm64)
      agy_url="$AGY_URL_ARM64"
      agy_sha="$AGY_SHA512_ARM64"
      ;;
    x86_64|amd64)
      agy_url="$AGY_URL_X64"
      agy_sha="$AGY_SHA512_X64"
      ;;
    *)
      echo "ERROR: Unsupported architecture for agy: $(uname -m)" >&2
      exit 1
      ;;
  esac

  agy_tmp="$(mktemp -d)"
  curl -fsSL "$agy_url" -o "$agy_tmp/agy.tar.gz"
  echo "$agy_sha  $agy_tmp/agy.tar.gz" | sha512sum -c -
  tar -xzf "$agy_tmp/agy.tar.gz" -C "$agy_tmp" antigravity
  install -m 755 "$agy_tmp/antigravity" "$HOME/.local/bin/agy"
  rm -rf "$agy_tmp"
  "$HOME/.local/bin/agy" install || true
fi
agy --version

mkdir -p "$HOME/.pi/agent"
git config --global --add safe.directory '*'
USER_SETUP

echo "== agy launcher wrapper"
cat > /usr/local/bin/agy <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -un)" != "agent" ]; then
  target_dir="$PWD"
  if [ "$target_dir" = "$HOME" ] || [ "$target_dir" = "/home/ubuntu" ]; then
    target_dir="/home/agent/workspace"
  fi
  exec sudo -u agent -i bash -c 'cd "$1" && shift && exec /home/agent/.local/bin/agy "$@"' -- "$target_dir" "$@"
fi

exec /home/agent/.local/bin/agy "$@"
WRAPPER
chmod 755 /usr/local/bin/agy

if ! sudo -u "$WORKBENCH_USER" -H git config --global user.name >/dev/null 2>&1 ||
   ! sudo -u "$WORKBENCH_USER" -H git config --global user.email >/dev/null 2>&1; then
  echo "NOTE: Set your git identity on the box:"
  echo "  git config --global user.name 'Your Name'"
  echo "  git config --global user.email 'you@example.com'"
fi

echo "== Done"
echo "The workbench is ready. Connect with start-aws-workbench, then run agy or pi."
