#!/usr/bin/env node
import { requestInstallationToken } from "/usr/local/lib/agent-workbench/github-app-token-client.mjs";

const [owner, repository] = process.argv.slice(2);

if (!owner || !repository) {
  process.stderr.write("Usage: gh-token <owner> <repository>\n");
  process.exit(1);
}

const response = requestInstallationToken(owner, repository);

if (response.errorMessage) {
  process.stderr.write(`The token function failed: ${response.errorMessage}\n`);
  process.exit(1);
}

if (!response.token) {
  process.stderr.write("The token function did not return a token.\n");
  process.exit(1);
}

process.stdout.write(response.token);
