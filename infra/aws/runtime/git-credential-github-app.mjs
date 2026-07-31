#!/usr/bin/env node
import { requestInstallationToken } from "/usr/local/lib/agent-workbench/github-app-token-client.mjs";

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
