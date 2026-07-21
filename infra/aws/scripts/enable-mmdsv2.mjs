import { execFileSync, spawnSync } from "node:child_process";

const STACK_NAME = "AgentWorkbenchStack";

const readOption = (name) => {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] ?? "" : "";
};

const runAws = (args) =>
  execFileSync("aws", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }).trim();

const findRuntimeId = (region) => {
  const stack = JSON.parse(
    runAws([
      "cloudformation",
      "describe-stacks",
      "--region",
      region,
      "--stack-name",
      STACK_NAME,
      "--output",
      "json",
    ]),
  ).Stacks?.[0];
  const runtimeArn = (stack?.Outputs ?? []).find(
    (output) => output.OutputKey === "AgentRuntimeArn",
  )?.OutputValue;

  return runtimeArn?.split("/").at(-1) ?? "";
};

const createUpdateInput = (runtime) => ({
  agentRuntimeId: runtime.agentRuntimeId,
  agentRuntimeArtifact: runtime.agentRuntimeArtifact,
  description: runtime.description,
  environmentVariables: runtime.environmentVariables,
  filesystemConfigurations: runtime.filesystemConfigurations,
  lifecycleConfiguration: runtime.lifecycleConfiguration,
  metadataConfiguration: { requireMMDSV2: true },
  networkConfiguration: runtime.networkConfiguration,
  protocolConfiguration: runtime.protocolConfiguration,
  requestHeaderConfiguration: runtime.requestHeaderConfiguration,
  roleArn: runtime.roleArn,
});

const pause = (milliseconds) => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
};

const waitForRuntime = (runtimeId, region) => {
  const maximumAttempts = 120;

  for (let attempt = 0; attempt < maximumAttempts; attempt += 1) {
    const runtime = JSON.parse(
      runAws([
        "bedrock-agentcore-control",
        "get-agent-runtime",
        "--region",
        region,
        "--agent-runtime-id",
        runtimeId,
        "--output",
        "json",
      ]),
    );

    if (runtime.status === "READY") {
      return;
    }

    if (runtime.status === "UPDATE_FAILED") {
      throw new Error(runtime.failureReason ?? "The MMDSv2 update failed.");
    }

    pause(5000);
  }

  throw new Error("Timed out waiting for the MMDSv2 update.");
};

const region = readOption("--region");
if (!region) {
  console.error("MMDSv2 configuration requires --region.");
  process.exit(1);
}

try {
  const runtimeId = findRuntimeId(region);
  if (!runtimeId) {
    throw new Error("Could not find the deployed AgentCore runtime ID.");
  }

  const runtime = JSON.parse(
    runAws([
      "bedrock-agentcore-control",
      "get-agent-runtime",
      "--region",
      region,
      "--agent-runtime-id",
      runtimeId,
      "--output",
      "json",
    ]),
  );

  if (runtime.metadataConfiguration?.requireMMDSV2 === true) {
    console.error("AgentCore MMDSv2 is already enabled.");
    process.exit(0);
  }

  const result = spawnSync(
    "aws",
    [
      "bedrock-agentcore-control",
      "update-agent-runtime",
      "--region",
      region,
      "--cli-input-json",
      JSON.stringify(createUpdateInput(runtime)),
      "--no-cli-pager",
    ],
    { stdio: "inherit" },
  );

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  waitForRuntime(runtimeId, region);
  console.error("AgentCore MMDSv2 enabled.");
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
