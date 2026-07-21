import http from "node:http";

const PORT = 8080;

const sendJson = (response, statusCode, payload) => {
  response.writeHead(statusCode, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
};

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url ?? "/", `http://${request.headers.host}`);

  if (request.method === "GET" && requestUrl.pathname === "/ping") {
    sendJson(response, 200, { status: "Healthy" });
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
