import { chmodSync, mkdirSync, rmSync } from "node:fs";
import http from "node:http";
import { dirname } from "node:path";
import { requestInstallationTokenAsync } from "./github-app-token-client.mjs";

const SOCKET_PATH = "/tmp/agent-workbench/github-token.sock";
const GITHUB_NAME = /^[A-Za-z0-9_.-]+$/u;

const sendJson = (response, statusCode, value) => {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(value));
};

const readJson = async (request) => {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
};

const handleRequest = async (request, response) => {
  if (request.method !== "POST" || request.url !== "/token") {
    sendJson(response, 404, { error: "Not found." });
    return;
  }

  const { owner, repository } = await readJson(request);
  if (!GITHUB_NAME.test(owner ?? "") || !GITHUB_NAME.test(repository ?? "")) {
    throw new Error("The GitHub repository is invalid.");
  }

  const result = await requestInstallationTokenAsync(owner, repository);
  if (!result.token) {
    throw new Error(result.errorMessage ?? "The token function returned no token.");
  }

  sendJson(response, 200, { token: result.token });
};

export const startGitHubTokenRelay = () => {
  mkdirSync(dirname(SOCKET_PATH), { recursive: true });
  rmSync(SOCKET_PATH, { force: true });

  const server = http.createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      sendJson(response, 500, { error: error.message });
    });
  });

  server.listen(SOCKET_PATH, () => chmodSync(SOCKET_PATH, 0o600));
};
