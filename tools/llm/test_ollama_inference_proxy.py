#!/usr/bin/env python3
"""Run with: python3 tools/llm/test_ollama_inference_proxy.py"""

import http.client
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from ollama_inference_proxy import InferenceProxy

REACHED_UPSTREAM = b"reached upstream"


class FakeOllama(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    requested_paths = []

    def do_GET(self):
        self.answer()

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.answer()

    def answer(self):
        FakeOllama.requested_paths.append(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        for piece in (b"reached ", b"upstream"):
            self.wfile.write(b"%x\r\n" % len(piece) + piece + b"\r\n")
        self.wfile.write(b"0\r\n\r\n")

    def log_message(self, *args):
        pass


def serve_in_background(handler):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class InferenceProxyTest(unittest.TestCase):
    def setUp(self):
        FakeOllama.requested_paths = []
        self.upstream = serve_in_background(FakeOllama)
        InferenceProxy.upstream_host, InferenceProxy.upstream_port = (
            self.upstream.server_address
        )
        self.proxy = serve_in_background(InferenceProxy)
        self.addCleanup(self.upstream.server_close)
        self.addCleanup(self.proxy.server_close)
        self.addCleanup(self.upstream.shutdown)
        self.addCleanup(self.proxy.shutdown)

    def call_proxy(self, method, path):
        connection = http.client.HTTPConnection(*self.proxy.server_address, timeout=5)
        try:
            connection.request(method, path, b"{}" if method == "POST" else None)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_forwards_inference_routes(self):
        for method, path in (
            ("GET", "/v1/models"),
            ("POST", "/v1/chat/completions"),
            ("POST", "/v1/completions"),
            ("POST", "/v1/embeddings"),
        ):
            with self.subTest(path=path):
                status, body = self.call_proxy(method, path)
                self.assertEqual(status, 200)
                self.assertEqual(body, REACHED_UPSTREAM)

    def test_keeps_the_query_string(self):
        status, _ = self.call_proxy("GET", "/v1/models?limit=1")

        self.assertEqual(status, 200)
        self.assertEqual(FakeOllama.requested_paths, ["/v1/models?limit=1"])

    def test_blocks_model_management_routes(self):
        for method, path in (
            ("POST", "/api/pull"),
            ("POST", "/api/create"),
            ("POST", "/api/push"),
            ("POST", "/api/blobs/sha256:1234"),
            ("GET", "/api/tags"),
            ("GET", "/api/ps"),
            ("POST", "/v1/models?x=/api/pull"),
            ("POST", "/v1/chat/completions/../../api/pull"),
        ):
            with self.subTest(path=path):
                status, _ = self.call_proxy(method, path)
                self.assertEqual(status, 403)

        self.assertEqual(FakeOllama.requested_paths, [])

    def test_blocks_unsupported_methods(self):
        status, _ = self.call_proxy("DELETE", "/api/delete")

        self.assertEqual(status, 501)
        self.assertEqual(FakeOllama.requested_paths, [])


if __name__ == "__main__":
    unittest.main()

