import { chmodSync, mkdirSync, rmSync } from "node:fs";
import http from "node:http";
import { dirname } from "node:path";
import { requestInstallationTokenAsync } from "./github-app-token-client.mjs";

export const GITHUB_TOKEN_SOCKET =
  "/tmp/agent-workbench/github-token.sock";
const MAX_REQUEST_BYTES = 4 * 1024;
const GITHUB_NAME_PATTERN = /^[A-Za-z0-9_.-]+$/u;

const readRequestBody = async (request) => {
  const chunks = [];
  let byteCount = 0;

  for await (const chunk of request) {
    byteCount += chunk.length;
    if (byteCount > MAX_REQUEST_BYTES) {
      throw new Error("The GitHub token request is too large.");
    }
    chunks.push(chunk);
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
};

const readInstallationToken = async (owner, repository) => {
  const response = await requestInstallationTokenAsync(owner, repository);

  if (response.errorMessage) {
    throw new Error(`The token function failed: ${response.errorMessage}`);
  }

  if (!response.token) {
    throw new Error("The token function did not return a token.");
  }

  return response.token;
};

const sendJson = (response, statusCode, payload) => {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
};

const checkRepository = (request) => {
  if (
    !GITHUB_NAME_PATTERN.test(request.owner ?? "") ||
    !GITHUB_NAME_PATTERN.test(request.repository ?? "")
  ) {
    throw new Error("The GitHub token request has an invalid repository.");
  }

  return {
    owner: request.owner,
    repository: request.repository,
  };
};

const handleRequest = async (request, response) => {
  if (request.method !== "POST" || request.url !== "/token") {
    sendJson(response, 404, { error: "Not found." });
    return;
  }

  const repository = checkRepository(await readRequestBody(request));
  const token = await readInstallationToken(
    repository.owner,
    repository.repository,
  );
  sendJson(response, 200, { token });
};

export const startGitHubTokenRelay = () => {
  mkdirSync(dirname(GITHUB_TOKEN_SOCKET), { recursive: true });
  rmSync(GITHUB_TOKEN_SOCKET, { force: true });

  const relay = http.createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      sendJson(response, 500, { error: error.message });
    });
  });

  relay.listen(GITHUB_TOKEN_SOCKET, () => {
    chmodSync(GITHUB_TOKEN_SOCKET, 0o600);
  });
};
