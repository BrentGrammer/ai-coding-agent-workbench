#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const readCredentialRequest = async () => {
  let input = "";

  for await (const chunk of process.stdin) {
    input += chunk;
  }

  return Object.fromEntries(
    input
      .split(/\r?\n/u)
      .filter(Boolean)
      .map((line) => {
        const separatorIndex = line.indexOf("=");
        return [line.slice(0, separatorIndex), line.slice(separatorIndex + 1)];
      }),
  );
};

// The App private key lives in the token function, not in this container, so
// the most this call can return is a one-hour token for a single repository.
const requestInstallationToken = (owner, repository) => {
  const responseDirectory = mkdtempSync(join(tmpdir(), "github-app-token-"));
  const responseFile = join(responseDirectory, "response.json");

  try {
    execFileSync(
      "aws",
      [
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
      { stdio: ["ignore", "ignore", "inherit"] },
    );

    return JSON.parse(readFileSync(responseFile, "utf8"));
  } finally {
    rmSync(responseDirectory, { recursive: true, force: true });
  }
};

const main = async () => {
  if (process.argv[2] !== "get") {
    return;
  }

  const credentialRequest = await readCredentialRequest();
  if (credentialRequest.host !== "github.com") {
    return;
  }

  const [owner, repositoryWithSuffix] = credentialRequest.path.split("/");
  const repository = repositoryWithSuffix?.replace(/\.git$/u, "");
  if (!owner || !repository) {
    throw new Error("The GitHub credential request did not include a repository.");
  }

  const response = requestInstallationToken(owner, repository);

  if (response.errorMessage) {
    throw new Error(`The token function failed: ${response.errorMessage}`);
  }

  if (!response.token) {
    throw new Error("The token function did not return a token.");
  }

  process.stdout.write(`username=x-access-token\npassword=${response.token}\n`);
};

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
