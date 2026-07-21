import { execFileSync, spawnSync } from "node:child_process";

const STACK_NAME = "AgentWorkbenchStack";
const DAEMON_WAIT_ATTEMPTS = 60;
const DAEMON_WAIT_MILLISECONDS = 2000;

const runQuietly = (command, args) => {
  try {
    return execFileSync(command, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
};

const findRegion = () =>
  process.env.AWS_REGION ||
  process.env.CDK_DEFAULT_REGION ||
  runQuietly("aws", ["configure", "get", "region"]);

const findImageUri = (region) => {
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
    return outputs.find((output) => output.OutputKey === "AgentCoreImageUri")
      ?.OutputValue;
  } catch {
    return "";
  }
};

const runMaintenance = (scriptName, args = []) => {
  const result = spawnSync("node", [`scripts/${scriptName}`, ...args], {
    stdio: "inherit",
  });

  if (result.status !== 0) {
    console.error(`Warning: ${scriptName} did not complete cleanly.`);
  }
};

const runRequiredMaintenance = (scriptName, args = []) => {
  const result = spawnSync("node", [`scripts/${scriptName}`, ...args], {
    stdio: "inherit",
  });

  if (result.status !== 0) {
    console.error(`${scriptName} failed.`);
    process.exit(result.status ?? 1);
  }
};

const pause = (milliseconds) => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
};

const checkDocker = () =>
  spawnSync("docker", ["info"], { stdio: "ignore" }).status === 0;

const startDocker = () => {
  if (process.platform === "darwin") {
    return spawnSync("open", ["-a", "Docker"], { stdio: "ignore" }).status === 0;
  }

  if (process.platform === "linux") {
    return (
      spawnSync("systemctl", ["start", "docker"], { stdio: "ignore" })
        .status === 0
    );
  }

  return false;
};

const waitForDocker = () => {
  if (checkDocker()) {
    return true;
  }

  if (!startDocker()) {
    return false;
  }

  for (let attempt = 0; attempt < DAEMON_WAIT_ATTEMPTS; attempt += 1) {
    if (checkDocker()) {
      return true;
    }

    pause(DAEMON_WAIT_MILLISECONDS);
  }

  return false;
};

if (!waitForDocker()) {
  console.error("Start Docker, then run npm run deploy again.");
  process.exit(1);
}

const region = findRegion();
if (!region) {
  console.error("Set AWS_REGION or configure a default AWS CLI region.");
  process.exit(1);
}

const previousImageUri = findImageUri(region);

const result = spawnSync(
  "npx",
  ["cdk", "deploy", STACK_NAME, ...process.argv.slice(2)],
  { stdio: "inherit" },
);

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

const currentImageUri = findImageUri(region);
runRequiredMaintenance("enable-mmdsv2.mjs", ["--region", region]);
runMaintenance("prune-workbench-images.mjs", [
  "--region",
  region,
  "--current",
  currentImageUri,
  "--previous",
  previousImageUri,
]);
runMaintenance("set-agentcore-log-retention.mjs", ["--region", region]);

process.exit(0);
