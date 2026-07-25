import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const STATE_FILE = path.join(
  homedir(),
  ".local",
  "state",
  "agent-workbench",
  "aws-sessions.json",
);

const readSavedSessions = () => {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return {};
  }
};

const probeSession = (name, session) => {
  console.log(`${name}  (${session.sessionId})`);

  try {
    execFileSync(
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

    console.log("  STILL ALIVE when probed. It is stopped now.");
    console.log("  So AWS does NOT end a dropped session on its own.");
  } catch (error) {
    const message = String(error.stderr ?? error.message);

    if (message.includes("ResourceNotFoundException")) {
      console.log("  ALREADY GONE before the probe.");
      console.log("  So AWS DOES end a dropped session on its own.");
    } else {
      console.log("  Probe failed for another reason:");
      console.log(`  ${message.trim()}`);
    }
  }
};

const sessions = readSavedSessions();
const names = Object.keys(sessions).sort();

if (names.length === 0) {
  console.log(`No saved sessions in ${STATE_FILE}`);
} else {
  for (const name of names) {
    probeSession(name, sessions[name]);
  }
}
