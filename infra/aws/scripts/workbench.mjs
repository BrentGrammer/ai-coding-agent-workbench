import { execFileSync, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, readSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const STACK_NAME = "AgentWorkbenchStack";
const RUNTIME_ARN_OUTPUT_KEY = "AgentRuntimeArn";
const DEFAULT_AGENT = "codex";
const BOOTSTRAP_TIMEOUT_SECONDS = 600;
const STATE_DIR = path.join(homedir(), ".local", "state", "agent-workbench");
const STATE_FILE = path.join(STATE_DIR, "aws-sessions.json");
const AGENTS = new Set(["codex", "claude", "opencode"]);
const MINIMUM_AGENTCORE_VERSION = [0, 24, 1];
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ESCAPE = String.fromCharCode(27);
const TERMINAL_RESET_CODES = {
  leaveAlternateScreen: `${ESCAPE}[?1049l`,
  softReset: `${ESCAPE}[!p`,
  stopFocusReports: `${ESCAPE}[?1004l`,
  stopX10MouseReports: `${ESCAPE}[?9l`,
  stopMouseClickReports: `${ESCAPE}[?1000l`,
  stopMouseDragReports: `${ESCAPE}[?1002l`,
  stopMouseMotionReports: `${ESCAPE}[?1003l`,
  stopUtf8MouseReports: `${ESCAPE}[?1005l`,
  stopSgrMouseReports: `${ESCAPE}[?1006l`,
  stopUrxvtMouseReports: `${ESCAPE}[?1015l`,
  stopBracketedPaste: `${ESCAPE}[?2004l`,
  popKittyKeyboardProtocol: `${ESCAPE}[<u`,
  stopModifyOtherKeys: `${ESCAPE}[>4;0m`,
  useNumericKeypad: `${ESCAPE}>`,
  useNormalCursorKeys: `${ESCAPE}[?1l`,
  enableAutoWrap: `${ESCAPE}[?7h`,
  clearScrollRegion: `${ESCAPE}[r`,
  useAsciiCharacterSet: `${ESCAPE}(B`,
  popWindowTitle: `${ESCAPE}[23;0t`,
  clearTextAttributes: `${ESCAPE}[0m`,
  showCursor: `${ESCAPE}[?25h`,
};
const LOCAL_TERMINAL_RESET_SEQUENCE =
  Object.values(TERMINAL_RESET_CODES).join("");
const INPUT_DISCARD_POLL_MS = 10;
const INPUT_DISCARD_QUIET_MS = 120;
const INPUT_DISCARD_TIMEOUT_MS = 500;

const RECONNECT_DELAY_MS = 2000;
const RECONNECT_ATTEMPT_LIMIT = 5;

const showUsage = () => {
  console.error(
    [
      "Usage:",
      "  workbench aws REPO_URL [--ref REF] [--agent codex|claude|opencode] [--keep NAME]",
      "  workbench aws reconnect NAME [--new-shell]",
      "  workbench aws stop NAME",
      "  workbench aws status",
    ].join("\n"),
  );
};

const runQuietly = (command, args, options = {}) => {
  try {
    return execFileSync(command, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      ...options,
    }).trim();
  } catch {
    return "";
  }
};

const findRegion = () => {
  const region =
    process.env.AWS_REGION ||
    process.env.CDK_DEFAULT_REGION ||
    runQuietly("aws", ["configure", "get", "region"]);

  if (!region) {
    throw new Error("Set AWS_REGION or configure a default AWS CLI region.");
  }

  return region;
};

const findRuntimeArn = (region) => {
  const stackJson = runQuietly("aws", [
    "cloudformation",
    "describe-stacks",
    "--region",
    region,
    "--stack-name",
    STACK_NAME,
    "--output",
    "json",
  ]);

  if (!stackJson) {
    return "";
  }

  try {
    const outputs = JSON.parse(stackJson).Stacks?.[0]?.Outputs ?? [];
    return outputs.find(
      (output) => output.OutputKey === RUNTIME_ARN_OUTPUT_KEY,
    )?.OutputValue;
  } catch {
    return "";
  }
};

const readSessions = () => {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return {};
  }
};

const writeSessions = (sessions) => {
  mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
  writeFileSync(STATE_FILE, `${JSON.stringify(sessions, null, 2)}\n`, {
    mode: 0o600,
  });
};

const validateRepoUrl = (repoUrl) => {
  const match = repoUrl.match(
    /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?$/u,
  );

  if (!match) {
    throw new Error("REPO_URL must be an HTTPS GitHub repository URL.");
  }
};

const validateName = (name) => {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/u.test(name)) {
    throw new Error("Session names may contain letters, digits, _ and -.");
  }
};

const validateRef = (repoRef) => {
  const result = spawnSync("git", ["check-ref-format", "--branch", repoRef], {
    stdio: "ignore",
  });

  if (result.status !== 0) {
    throw new Error(`Invalid Git ref: ${repoRef}`);
  }
};

const parseLaunchArguments = (args) => {
  const session = {
    repoUrl: args[0],
    agent: DEFAULT_AGENT,
  };

  if (!session.repoUrl) {
    throw new Error("REPO_URL is required.");
  }

  for (let index = 1; index < args.length; index += 1) {
    const option = args[index];
    const value = args[index + 1];

    if (!["--ref", "--agent", "--keep"].includes(option) || !value) {
      throw new Error(`Invalid option: ${option}`);
    }

    if (option === "--ref") {
      session.repoRef = value;
    }

    if (option === "--agent") {
      session.agent = value;
    }

    if (option === "--keep") {
      session.name = value;
    }

    index += 1;
  }

  validateRepoUrl(session.repoUrl);
  if (session.repoRef) {
    validateRef(session.repoRef);
  }

  if (!AGENTS.has(session.agent)) {
    throw new Error(`Unsupported agent: ${session.agent}`);
  }

  if (session.name) {
    validateName(session.name);
  }

  return session;
};

const quoteShell = (value) => `'${String(value).replaceAll("'", "'\\''")}'`;

const readGitIdentity = () => ({
  name: runQuietly("git", ["config", "--global", "--get", "user.name"]),
  email: runQuietly("git", ["config", "--global", "--get", "user.email"]),
});

const createBootstrapCommand = (session) => {
  const gitIdentity = readGitIdentity();
  const githubAppIdParameterName =
    process.env.GITHUB_APP_ID_PARAMETER_NAME;
  const githubAppPrivateKeyParameterName =
    process.env.GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME;

  if (!githubAppIdParameterName || !githubAppPrivateKeyParameterName) {
    throw new Error(
      "Set the GitHub App Parameter Store names before launching AgentCore.",
    );
  }

  const exports = [
    ["REPO_URL", session.repoUrl],
    ["REPO_REF", session.repoRef],
    ["WORKBENCH_AGENT", session.agent],
    ["WORKBENCH_SESSION", session.name ?? session.sessionId],
    ["AWS_REGION", session.region],
    ["GITHUB_APP_ID_PARAMETER_NAME", githubAppIdParameterName],
    [
      "GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME",
      githubAppPrivateKeyParameterName,
    ],
    ["GIT_USER_NAME", gitIdentity.name],
    ["GIT_USER_EMAIL", gitIdentity.email],
  ]
    .filter(([, value]) => value)
    .map(([name, value]) => `export ${name}=${quoteShell(value)}`);

  return `/bin/bash -lc ${quoteShell(
    [...exports, "/usr/local/bin/bootstrap-repo"].join(" && "),
  )}`;
};

const runAgentCore = (args) =>
  spawnSync("agentcore", args, { stdio: "inherit" });

const sleepSync = (milliseconds) => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
};

const setTerminalModes = (args) =>
  spawnSync("stty", args, {
    encoding: "utf8",
    stdio: ["inherit", "pipe", "ignore"],
  });

const readTerminalModes = () => {
  if (!process.stdin.isTTY) {
    return "";
  }

  const result = setTerminalModes(["-g"]);
  return result.status === 0 ? result.stdout.trim() : "";
};

const discardPendingTerminalInput = () => {
  if (setTerminalModes(["raw", "-echo", "min", "0", "time", "1"]).status !== 0) {
    return;
  }

  const discardBuffer = Buffer.alloc(4096);
  const giveUpAt = Date.now() + INPUT_DISCARD_TIMEOUT_MS;
  let quietAt = Date.now() + INPUT_DISCARD_QUIET_MS;

  while (Date.now() < giveUpAt && Date.now() < quietAt) {
    let bytesRead = 0;

    try {
      bytesRead = readSync(0, discardBuffer, 0, discardBuffer.length, null);
    } catch (error) {
      if (error.code !== "EAGAIN") {
        return;
      }
    }

    if (bytesRead === 0) {
      sleepSync(INPUT_DISCARD_POLL_MS);
      continue;
    }

    quietAt = Date.now() + INPUT_DISCARD_QUIET_MS;
  }
};

const restoreLocalTerminal = (savedTerminalModes) => {
  if (process.stdin.isTTY) {
    discardPendingTerminalInput();
    setTerminalModes(savedTerminalModes ? [savedTerminalModes] : ["sane"]);
  }

  if (process.stdout.isTTY) {
    process.stdout.write(LOCAL_TERMINAL_RESET_SEQUENCE);
  }
};

const checkAgentCoreVersion = () => {
  const versionOutput = runQuietly("agentcore", ["--version"]);
  const versionMatch = versionOutput.match(/(\d+)\.(\d+)\.(\d+)/u);

  if (!versionMatch) {
    throw new Error(
      "Install the AgentCore CLI with: npm install -g @aws/agentcore@latest",
    );
  }

  const installedVersion = versionMatch.slice(1).map(Number);
  for (let index = 0; index < MINIMUM_AGENTCORE_VERSION.length; index += 1) {
    if (installedVersion[index] > MINIMUM_AGENTCORE_VERSION[index]) {
      return;
    }

    if (installedVersion[index] < MINIMUM_AGENTCORE_VERSION[index]) {
      throw new Error(
        "Update the AgentCore CLI with: npm install -g @aws/agentcore@latest",
      );
    }
  }
};

const applyLogRetention = (region) => {
  const result = spawnSync(
    "node",
    [
      path.join(SCRIPT_DIR, "set-agentcore-log-retention.mjs"),
      "--region",
      region,
    ],
    { stdio: "inherit" },
  );

  if (result.status !== 0) {
    console.error("Warning: Could not apply workbench log retention.");
  }
};

const bootstrapSession = (session) => {
  const refDescription = session.repoRef ?? "its default branch";
  console.error(`Preparing ${session.repoUrl} at ${refDescription}...`);
  const result = runAgentCore([
    "exec",
    "--runtime",
    session.runtimeArn,
    "--region",
    session.region,
    "--session-id",
    session.sessionId,
    "--timeout",
    String(BOOTSTRAP_TIMEOUT_SECONDS),
    createBootstrapCommand(session),
  ]);

  if (result.error) {
    throw new Error(`Could not run AgentCore: ${result.error.message}`);
  }

  if (result.status !== 0) {
    throw new Error("Repository bootstrap failed.");
  }
};

const stopSession = (session) => {
  const result = spawnSync(
    "aws",
    [
      "bedrock-agentcore",
      "stop-runtime-session",
      "--region",
      session.region,
      "--agent-runtime-arn",
      session.runtimeArn,
      "--runtime-session-id",
      session.sessionId,
      "--no-cli-pager",
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  );

  if (
    result.status !== 0 &&
    !result.stderr?.includes("ResourceNotFoundException")
  ) {
    process.stderr.write(result.stderr ?? "Could not stop the session.\n");
    return false;
  }

  return true;
};

const buildShellId = (session) =>
  `${session.agent}-${session.sessionId}-${session.shellGeneration ?? 0}`;

const attachSession = (session) => {
  console.error(
    `Opening ${session.agent} session ${session.name ?? "temporary"}...`,
  );
  const savedTerminalModes = readTerminalModes();
  const restore = () => restoreLocalTerminal(savedTerminalModes);
  process.once("exit", restore);
  let result;

  try {
    result = runAgentCore([
      "exec",
      "--it",
      "--runtime",
      session.runtimeArn,
      "--region",
      session.region,
      "--session-id",
      session.sessionId,
      "--shell-id",
      buildShellId(session),
    ]);
  } finally {
    process.removeListener("exit", restore);
    restore();
  }

  if (result.error) {
    throw new Error(`Could not run AgentCore: ${result.error.message}`);
  }

  return result.status ?? 1;
};

const connectSession = (session, keepSession) => {
  let cleanupStarted = false;

  const cleanup = () => {
    if (keepSession || cleanupStarted) {
      return;
    }

    cleanupStarted = true;
    stopSession(session);
  };

  const exitForSignal = (exitCode) => {
    cleanup();
    process.exit(exitCode);
  };

  process.once("SIGHUP", () => exitForSignal(129));
  process.once("SIGINT", () => exitForSignal(130));
  process.once("SIGTERM", () => exitForSignal(143));
  process.once("exit", cleanup);

  bootstrapSession(session);

  let exitCode = attachSession(session);
  let reconnectAttempt = 0;

  while (exitCode !== 0 && reconnectAttempt < RECONNECT_ATTEMPT_LIMIT) {
    reconnectAttempt += 1;
    console.error(
      `\nShell disconnected. Reconnecting (${reconnectAttempt}/${RECONNECT_ATTEMPT_LIMIT})...`,
    );
    sleepSync(RECONNECT_DELAY_MS);
    exitCode = attachSession(session);
  }

  if (exitCode !== 0) {
    console.error("\nCould not reconnect to the AgentCore shell.");
  }

  cleanup();
  applyLogRetention(session.region);
  return exitCode;
};

const createSession = (launchOptions) => {
  const region = findRegion();
  const runtimeArn = findRuntimeArn(region);

  if (!runtimeArn) {
    throw new Error(
      `Deploy ${STACK_NAME} in ${region} before opening a workbench.`,
    );
  }

  return {
    ...launchOptions,
    region,
    runtimeArn,
    sessionId: randomUUID(),
  };
};

const launchSession = (args) => {
  const launchOptions = parseLaunchArguments(args);
  const sessions = readSessions();
  let session = createSession(launchOptions);

  if (launchOptions.name && sessions[launchOptions.name]) {
    session = sessions[launchOptions.name];

    if (
      session.repoUrl !== launchOptions.repoUrl ||
      session.repoRef !== launchOptions.repoRef ||
      session.agent !== launchOptions.agent
    ) {
      throw new Error(
        `Session ${launchOptions.name} already has another configuration.`,
      );
    }
  }

  if (session.name) {
    sessions[session.name] = session;
    writeSessions(sessions);
  }

  return connectSession(session, Boolean(session.name));
};

const reconnectSession = (name, startNewShell) => {
  validateName(name);
  const sessions = readSessions();
  const session = sessions[name];

  if (!session) {
    throw new Error(`Unknown session: ${name}`);
  }

  if (startNewShell) {
    session.shellGeneration = (session.shellGeneration ?? 0) + 1;
    sessions[name] = session;
    writeSessions(sessions);
    console.error(`Abandoning the previous shell for ${name}.`);
  }

  return connectSession(session, true);
};

const stopNamedSession = (name) => {
  validateName(name);
  const sessions = readSessions();
  const session = sessions[name];

  if (!session) {
    throw new Error(`Unknown session: ${name}`);
  }

  if (!stopSession(session)) {
    return 1;
  }

  delete sessions[name];
  writeSessions(sessions);
  console.error(`Stopped ${name} and removed its local session record.`);
  return 0;
};

const showStatus = () => {
  const region = findRegion();
  const endTime = new Date();
  const startTime = new Date(endTime.getTime() - 15 * 60 * 1000);
  const activeSessionCount = runQuietly("aws", [
    "cloudwatch",
    "get-metric-statistics",
    "--region",
    region,
    "--namespace",
    "AWS/Bedrock-AgentCore",
    "--metric-name",
    "ActiveSessionCount",
    "--dimensions",
    "Name=Service,Value=AgentCore.Runtime",
    "--start-time",
    startTime.toISOString(),
    "--end-time",
    endTime.toISOString(),
    "--period",
    "60",
    "--statistics",
    "Maximum",
    "--query",
    "sort_by(Datapoints,&Timestamp)[-1].Maximum",
    "--output",
    "text",
  ]);
  const runtimeArn = findRuntimeArn(region);

  console.log(`Region: ${region}`);
  console.log(`Active AgentCore runtime sessions: ${activeSessionCount || "no metric data"}`);
  console.log(`Workbench runtime: ${runtimeArn || "not deployed"}`);
  console.log("A deployed READY runtime is not necessarily an active session.");
  return 0;
};

const main = () => {
  const args = process.argv.slice(2);

  if (args[0] === "status" && args.length === 1) {
    return showStatus();
  }

  if (args[0] === "reconnect" && args.length >= 2 && args.length <= 3) {
    if (args.length === 3 && args[2] !== "--new-shell") {
      throw new Error(`Invalid option: ${args[2]}`);
    }

    checkAgentCoreVersion();
    return reconnectSession(args[1], args[2] === "--new-shell");
  }

  if (args[0] === "stop" && args.length === 2) {
    return stopNamedSession(args[1]);
  }

  checkAgentCoreVersion();
  return launchSession(args);
};

try {
  process.exitCode = main();
} catch (error) {
  console.error(error.message);
  showUsage();
  process.exitCode = 1;
}
