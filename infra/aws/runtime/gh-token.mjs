#!/usr/bin/env node
import http from "node:http";

const [owner, repository] = process.argv.slice(2);
const body = Buffer.from(JSON.stringify({ owner, repository }));

if (!owner || !repository) {
  process.stderr.write("Usage: gh-token <owner> <repository>\n");
  process.exit(1);
}

const request = http.request(
  {
    socketPath: "/tmp/agent-workbench/github-token.sock",
    path: "/token",
    method: "POST",
    headers: {
      "content-length": body.length,
      "content-type": "application/json",
    },
  },
  (response) => {
    const chunks = [];
    response.on("data", (chunk) => chunks.push(chunk));
    response.on("end", () => {
      try {
        const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (response.statusCode !== 200 || !result.token) {
          throw new Error(result.error ?? "The GitHub token request failed.");
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
