import http from "node:http";
import { readdirSync, readFileSync } from "node:fs";

const PORT = 8080;
const STATUS_HEALTHY = "Healthy";
const STATUS_HEALTHY_BUSY = "HealthyBusy";
const HERDR_PROCESS_NAME = "herdr";

const sendJson = (response, statusCode, payload) => {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
};

const isHerdrRunning = () => {
  for (const entry of readdirSync("/proc")) {
    if (!/^\d+$/u.test(entry)) {
      continue;
    }

    try {
      const processName = readFileSync(`/proc/${entry}/comm`, "utf8").trim();
      if (processName === HERDR_PROCESS_NAME) {
        return true;
      }
    } catch {
      continue;
    }
  }

  return false;
};

let lastStatus = null;
let lastStatusChangeUnixSeconds = null;

const buildPingPayload = () => {
  // AgentCore treats Healthy as idle and may stop the session after the idle timeout.
  const status = isHerdrRunning() ? STATUS_HEALTHY_BUSY : STATUS_HEALTHY;
  const nowUnixSeconds = Math.floor(Date.now() / 1000);

  if (status !== lastStatus) {
    lastStatus = status;
    lastStatusChangeUnixSeconds = nowUnixSeconds;
  }

  return {
    status,
    time_of_last_update: lastStatusChangeUnixSeconds,
  };
};

const server = http.createServer((request, response) => {
  const requestUrl = new URL(
    request.url ?? "/",
    `http://${request.headers.host}`,
  );

  if (request.method === "GET" && requestUrl.pathname === "/ping") {
    sendJson(response, 200, buildPingPayload());
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/invocations") {
    request.resume();
    request.on("end", () => {
      sendJson(response, 200, {
        message: "Connect with the AgentCore interactive shell.",
      });
    });
    return;
  }

  sendJson(response, 404, { status: "not-found" });
});

server.listen(PORT, "0.0.0.0");
