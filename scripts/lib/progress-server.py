#!/usr/bin/env python3
"""Small localhost-only server for the progress companion page."""

from __future__ import annotations

import argparse
import functools
import http.server
import socketserver
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    token = None

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def list_directory(self, path: str):
        self.send_error(403, "Directory listing is disabled")
        return None

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path not in ("/progress.html", "/progress.js", "/progress.json"):
            self.send_error(404, "Not found")
            return
        if parsed.path not in ("/progress.html", "/progress.js"):
            query = parse_qs(parsed.query)
            if query.get("token", [""])[0] != self.token:
                self.send_error(403, "Invalid progress token")
                return
        super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token", required=True)
    args = parser.parse_args()

    NoCacheHandler.token = args.token
    handler = functools.partial(NoCacheHandler, directory=str(args.directory.resolve()))
    with ReusableTCPServer(("127.0.0.1", args.port), handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
