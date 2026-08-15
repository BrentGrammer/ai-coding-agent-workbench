#!/usr/bin/env python3
"""Serves only the OpenAI-compatible inference routes of a local Ollama.

Ollama has no authentication, so whatever reaches its port can also pull,
create, and delete models, and a pull fetches from any registry host the
caller names. Agents run untrusted code, so they get this proxy instead of
the Ollama port itself.

Usage: ollama_inference_proxy.py [LISTEN_HOST:PORT] [OLLAMA_HOST:PORT]
"""

import http.client
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ALLOWED_ROUTES = frozenset(
    {
        ("GET", "/v1/models"),
        ("POST", "/v1/chat/completions"),
        ("POST", "/v1/completions"),
        ("POST", "/v1/embeddings"),
    }
)

# These describe a single connection, so passing them on corrupts the next one.
HOP_BY_HOP_HEADERS = frozenset(
    {
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    }
)

READ_BYTES = 65536
UPSTREAM_TIMEOUT_SECONDS = 600


def split_host_port(value, default_port):
    host, separator, port = value.rpartition(":")
    if not separator:
        return value, default_port
    return host, int(port)


class InferenceProxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    disable_nagle_algorithm = True
    upstream_host = "127.0.0.1"
    upstream_port = 11434

    def do_GET(self):
        self.forward("GET")

    def do_POST(self):
        self.forward("POST")

    def forward(self, method):
        route = self.path.split("?", 1)[0]
        if (method, route) not in ALLOWED_ROUTES:
            self.send_error(403, "Route not allowed")
            return

        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        upstream = http.client.HTTPConnection(
            self.upstream_host,
            self.upstream_port,
            timeout=UPSTREAM_TIMEOUT_SECONDS,
        )
        try:
            upstream.request(method, self.path, body, self.forwarded_headers())
            self.stream_response(upstream.getresponse())
        except OSError as error:
            self.send_error(502, "Cannot reach the model server", str(error))
        finally:
            upstream.close()

    def forwarded_headers(self):
        return {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
        }

    def stream_response(self, response):
        self.send_response(response.status)
        for name, value in response.getheaders():
            if name.lower() not in HOP_BY_HOP_HEADERS:
                self.send_header(name, value)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        while True:
            # read1 hands over each piece as it arrives, so tokens stream out
            # instead of waiting for a full buffer.
            piece = response.read1(READ_BYTES)
            if not piece:
                break
            self.wfile.write(b"%x\r\n" % len(piece) + piece + b"\r\n")
        self.wfile.write(b"0\r\n\r\n")


def main():
    listen = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:11435"
    upstream = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1:11434"
    listen_host, listen_port = split_host_port(listen, 11435)
    InferenceProxy.upstream_host, InferenceProxy.upstream_port = split_host_port(
        upstream, 11434
    )

    server = ThreadingHTTPServer((listen_host, listen_port), InferenceProxy)
    print(f"Inference routes of {upstream} served on {listen_host}:{listen_port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
