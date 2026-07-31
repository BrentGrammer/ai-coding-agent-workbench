#!/usr/bin/env node
import http from "node:http";

const GITHUB_TOKEN_SOCKET = "/tmp/agent-workbench/github-token.sock";
const MAX_RESPONSE_BYTES = 64 * 1024;

const [owner, repository] = process.argv.slice(2);

if (!owner || !repository) {
  process.stderr.write("Usage: gh-token <owner> <repository>\n");
  process.exit(1);
}

const body = Buffer.from(JSON.stringify({ owner, repository }));
const request = http.request(
  {
    socketPath: GITHUB_TOKEN_SOCKET,
    path: "/token",
    method: "POST",
    headers: {
      "content-length": body.length,
      "content-type": "application/json",
    },
  },
  (response) => {
    const chunks = [];
    let byteCount = 0;

    response.on("data", (chunk) => {
      byteCount += chunk.length;
      if (byteCount > MAX_RESPONSE_BYTES) {
        request.destroy(new Error("The GitHub token response is too large."));
        return;
      }
      chunks.push(chunk);
    });
    response.on("end", () => {
      try {
        const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (response.statusCode !== 200) {
          throw new Error(result.error ?? "The GitHub token request failed.");
        }
        if (typeof result.token !== "string" || result.token.length === 0) {
          throw new Error("The GitHub token response is invalid.");
        }
        process.stdout.write(result.token);
      } catch (error) {
        process.stderr.write(`${error.message}\n`);
        process.exitCode = 1;
      }
    });
  },
);

request.on("error", (error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
request.end(body);
