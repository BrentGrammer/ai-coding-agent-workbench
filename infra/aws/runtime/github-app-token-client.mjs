import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The App private key lives in the token function, not in this container, so
// the most this call can return is a one-hour token for a single repository.
export const requestInstallationToken = (owner, repository) => {
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
