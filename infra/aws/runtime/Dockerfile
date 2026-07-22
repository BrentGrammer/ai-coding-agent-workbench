FROM node:24-bookworm-slim

# pinned aws cli - update when needed
ARG AWS_CLI_VERSION=2.36.4
ARG HERDR_VERSION=0.7.4
ARG HUNK_VERSION=0.17.3

ENV DO_NOT_TRACK=1 \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_FEEDBACK_COMMAND=1 \
    CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1 \
    GEMINI_TELEMETRY_ENABLED=false \
    GEMINI_TELEMETRY_TRACES_ENABLED=false \
    GEMINI_TELEMETRY_LOG_PROMPTS=false \
    OPENCODE_DISABLE_SHARE=1 \
    OPENCODE_AUTO_SHARE=false \
    TERM=xterm-256color

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      bubblewrap \
      socat \
      ca-certificates \
      curl \
      git \
      gnupg \
      less \
      ncurses-bin \
      ncurses-term \
      openssh-client \
      unzip \
    && rm -rf /var/lib/apt/lists/*

COPY infra/aws/runtime/aws-cli-public-key.asc /tmp/aws-cli-public-key.asc
COPY infra/aws/runtime/install-aws-cli.sh /tmp/install-aws-cli.sh

RUN /bin/bash /tmp/install-aws-cli.sh "$AWS_CLI_VERSION" \
    && rm -f /tmp/aws-cli-public-key.asc /tmp/install-aws-cli.sh

RUN herdr_arch="$(uname -m)" \
    && if [ "$herdr_arch" = "x86_64" ]; then herdr_arch="x86_64"; else herdr_arch="aarch64"; fi \
    && curl -fsSL "https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${herdr_arch}" -o /usr/local/bin/herdr \
    && chmod 755 /usr/local/bin/herdr \
    && herdr --version

RUN useradd --create-home --shell /bin/bash agent \
    && mkdir -p /etc/agent-workbench /home/agent/.local/npm \
    && chown -R agent:agent /home/agent \
    && printf '%s\n' \
      'export PATH="/home/agent/.local/npm/bin:$PATH"' \
      > /etc/profile.d/agent-npm.sh

ENV NPM_CONFIG_PREFIX=/home/agent/.local/npm \
    PATH="/home/agent/.local/npm/bin:${PATH}"

USER agent

RUN npm install -g \
      "hunkdiff@${HUNK_VERSION}" \
      @anthropic-ai/claude-code@latest \
      @openai/codex@latest \
      opencode-ai@latest \
    && cd "$(npm root -g)/opencode-ai" \
    && node postinstall.mjs \
    && hunk --version \
    && claude --version \
    && codex --version \
    && opencode --version

USER root

COPY infra/aws/runtime/agentcore-server.mjs /app/agentcore-server.mjs
COPY infra/aws/runtime/git-credential-github-app.mjs /usr/local/bin/git-credential-github-app
COPY infra/aws/runtime/bootstrap-repo.sh /usr/local/bin/bootstrap-repo
COPY infra/aws/runtime/workbench-profile.sh /etc/profile.d/workbench.sh
COPY runtime/start-herdr /usr/local/bin/start-herdr
COPY runtime/workbench-pane-shell /usr/local/bin/workbench-pane-shell
COPY runtime/deny-protected-file-reads /usr/local/bin/deny-protected-file-reads
COPY runtime/herdr-config.toml /etc/agent-workbench/herdr-config.toml
COPY tools/agents/claude-settings.json /etc/claude-code/managed-settings.json
COPY tools/agents/codex-config.toml /etc/agent-workbench/codex-config.toml
COPY tools/agents/opencode.json /etc/opencode/opencode.json

RUN chmod 755 \
      /usr/local/bin/git-credential-github-app \
      /usr/local/bin/bootstrap-repo \
      /usr/local/bin/deny-protected-file-reads \
      /usr/local/bin/start-herdr \
      /usr/local/bin/workbench-pane-shell \
    && chown -R root:root /etc/claude-code /etc/opencode \
    && chmod 755 /etc/claude-code /etc/opencode \
    && chmod 644 \
      /etc/profile.d/workbench.sh \
      /etc/agent-workbench/herdr-config.toml \
      /etc/claude-code/managed-settings.json \
      /etc/agent-workbench/codex-config.toml \
      /etc/opencode/opencode.json

USER agent
WORKDIR /home/agent

EXPOSE 8080

CMD ["node", "/app/agentcore-server.mjs"]
