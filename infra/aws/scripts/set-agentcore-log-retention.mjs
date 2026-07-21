import { execFileSync, spawnSync } from "node:child_process";

const LOG_GROUP_PREFIX = "/aws/bedrock-agentcore/runtimes/agent_workbench-";
const RETENTION_DAYS = 1;

const readOption = (name) => {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] ?? "" : "";
};

const listLogGroups = (region) => {
  try {
    const output = execFileSync(
      "aws",
      [
        "logs",
        "describe-log-groups",
        "--region",
        region,
        "--log-group-name-prefix",
        LOG_GROUP_PREFIX,
        "--output",
        "json",
        "--no-cli-pager",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
    );

    return JSON.parse(output).logGroups ?? [];
  } catch {
    return [];
  }
};

const region = readOption("--region");
if (!region) {
  console.error("Log retention requires --region.");
  process.exit(1);
}

const logGroups = listLogGroups(region);
for (const logGroup of logGroups) {
  if (logGroup.retentionInDays === RETENTION_DAYS) {
    continue;
  }

  const result = spawnSync(
    "aws",
    [
      "logs",
      "put-retention-policy",
      "--region",
      region,
      "--log-group-name",
      logGroup.logGroupName,
      "--retention-in-days",
      String(RETENTION_DAYS),
      "--no-cli-pager",
    ],
    { stdio: "inherit" },
  );

  if (result.status !== 0) {
    process.exitCode = 1;
  }
}

console.error(
  `Workbench log retention complete: ${logGroups.length} group(s) checked.`,
);
