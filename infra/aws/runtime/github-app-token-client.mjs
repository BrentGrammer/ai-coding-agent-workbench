import { execFile, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

// The App private key lives in the token function, not in this container, so
// the most this call can return is a one-hour token for a single repository.
const execFileAsync = promisify(execFile);

const createInvocation = (owner, repository) => {
  const responseDirectory = mkdtempSync(join(tmpdir(), "github-app-token-"));
  const responseFile = join(responseDirectory, "response.json");

  return {
    args: [
      "lambda",
      "invoke",
      "--region",
      process.env.AWS_REGION,
      "--function-name",
      process.env.GITHUB_APP_TOKEN_FUNCTION_NAME,
      "--cli-binary-format",
      "raw-in-base64-out",
      "--payload",
      JSON.stringify({ owner, repository }),
      responseFile,
    ],
    responseDirectory,
    responseFile,
  };
};

export const requestInstallationToken = (owner, repository) => {
  const invocation = createInvocation(owner, repository);

  try {
    execFileSync("aws", invocation.args, {
      stdio: ["ignore", "ignore", "inherit"],
    });

    return JSON.parse(readFileSync(invocation.responseFile, "utf8"));
  } finally {
    rmSync(invocation.responseDirectory, { recursive: true, force: true });
  }
};

export const requestInstallationTokenAsync = async (owner, repository) => {
  const invocation = createInvocation(owner, repository);

  try {
    await execFileAsync("aws", invocation.args);
    return JSON.parse(readFileSync(invocation.responseFile, "utf8"));
  } finally {
    rmSync(invocation.responseDirectory, { recursive: true, force: true });
  }
};
