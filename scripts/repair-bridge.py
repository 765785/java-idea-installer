#!/usr/bin/env python3
"""Authenticated loopback bridge used by the public repair button."""

from __future__ import annotations

import argparse
import hmac
import http.server
import json
import os
import shlex
# Only the fixed osascript executable is launched; shell execution is never used.
import subprocess  # nosec B404
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

class BridgeServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, address, handler, *, root: Path, token: str, progress_file: Path, idle_minutes: int):
        super().__init__(address, handler)
        self.root = root
        self.token = token
        self.progress_file = progress_file
        self.idle_seconds = idle_minutes * 60
        self.last_request = time.monotonic()
        self.lock = threading.Lock()
        self.current_job: dict[str, object] | None = None
        self.seen_requests: dict[str, dict[str, object]] = {}

    def touch(self) -> None:
        self.last_request = time.monotonic()

    def job_status(self, job: dict[str, object]) -> str:
        if self.progress_file.is_file():
            try:
                progress = json.loads(self.progress_file.read_text(encoding="utf-8"))
                status = progress.get("status")
                if status == "success":
                    return "completed"
                if status in ("failed", "partial"):
                    return "failed"
                if status == "running":
                    return "running"
            except (OSError, ValueError):
                return "running"
        process = job["process"]
        if process.poll() is not None and time.monotonic() - job["startedAt"] > 20:
            return "failed"
        return "running"


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    server: BridgeServer

    def log_message(self, format: str, *args: object) -> None:
        return

    def send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path: Path, content_type: str) -> None:
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def token_valid(self) -> bool:
        candidate = self.headers.get("X-Java-Setup-Token", "")
        return hmac.compare_digest(candidate.lower(), self.server.token.lower())

    def origin_valid(self) -> bool:
        origin = self.headers.get("Origin", "")
        local = f"http://127.0.0.1:{self.server.server_port}"
        return origin == local

    def do_GET(self) -> None:
        self.server.touch()
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {"status": "ok"})
            return
        if path == "/launch":
            self.send_file(self.server.root / "repair-launch.html", "text/html; charset=utf-8")
            return
        if path == "/repair-launch.js":
            self.send_file(self.server.root / "repair-launch.js", "text/javascript; charset=utf-8")
            return
        if path == "/api/status":
            if not self.token_valid():
                self.send_json(403, {"status": "error", "message": "Invalid token."})
                return
            with self.server.lock:
                job = self.server.current_job
                if not job:
                    self.send_json(200, {"status": "idle"})
                    return
                process = job["process"]
                exit_code = process.poll()
                status = self.server.job_status(job)
                self.send_json(
                    200,
                    {
                        "status": status,
                        "jobId": job["jobId"],
                        "exitCode": exit_code,
                    },
                )
            return
        self.send_json(404, {"status": "error", "message": "Not found."})

    def do_POST(self) -> None:
        self.server.touch()
        if urlparse(self.path).path != "/api/repair-all":
            self.send_json(404, {"status": "error", "message": "Not found."})
            return
        if not self.origin_valid():
            self.send_json(403, {"status": "error", "message": "Invalid origin."})
            return
        if not self.token_valid():
            self.send_json(403, {"status": "error", "message": "Invalid token."})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > 4096:
            self.send_json(413, {"status": "error", "message": "Request too large."})
            return
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, TypeError):
            self.send_json(400, {"status": "error", "message": "Invalid JSON."})
            return
        if not isinstance(payload, dict):
            self.send_json(400, {"status": "error", "message": "Invalid JSON object."})
            return

        request_id = str(payload.get("requestId", ""))
        if payload.get("action") != "fix-all" or not re_full_hex(request_id, 32):
            self.send_json(400, {"status": "error", "message": "Invalid repair request."})
            return

        with self.server.lock:
            if request_id in self.server.seen_requests:
                self.send_json(200, {"status": "accepted", "jobId": self.server.seen_requests[request_id]["jobId"]})
                return
            current = self.server.current_job
            if current and self.server.job_status(current) == "running":
                self.send_json(409, {"status": "busy", "message": "A repair task is already running."})
                return

            try:
                if self.server.progress_file.exists():
                    self.server.progress_file.unlink()
                process = start_terminal(self.server.root)
            except Exception:
                self.send_json(500, {"status": "error", "message": "Could not start Terminal."})
                return

            job_id = uuid.uuid4().hex
            job = {
                "jobId": job_id,
                "requestId": request_id,
                "process": process,
                "startedAt": time.monotonic(),
            }
            self.server.current_job = job
            self.server.seen_requests[request_id] = job

        self.send_json(200, {"status": "accepted", "jobId": job_id})

def re_full_hex(value: str, length: int) -> bool:
    return len(value) == length and all(char in "0123456789abcdefABCDEF" for char in value)


def start_terminal(root: Path) -> subprocess.Popen:
    command = f"cd {shlex.quote(str(root))} && ./install.sh --fix-all"
    escaped = command.replace("\\", "\\\\").replace('"', '\\"')
    script = f'tell application "Terminal" to do script "{escaped}"'
    environment = os.environ.copy()
    environment["JAVA_SETUP_NO_BRIDGE"] = "1"
    # Executable and arguments are fixed by the bridge; shell=False is explicit.
    return subprocess.Popen(  # nosec B603
        ["/usr/bin/osascript", "-e", script],
        env=environment,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolkit-root", required=True, type=Path)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--token", required=True)
    parser.add_argument("--progress-file", required=True, type=Path)
    parser.add_argument("--idle-minutes", type=int, default=30)
    args = parser.parse_args()

    root = args.toolkit_root.resolve()
    if not re_full_hex(args.token, 64):
        raise SystemExit("Invalid bridge token.")
    if not (root / "install.sh").is_file():
        raise SystemExit("install.sh was not found.")

    server = BridgeServer(
        ("127.0.0.1", args.port),
        BridgeHandler,
        root=root,
        token=args.token,
        progress_file=args.progress_file.resolve(),
        idle_minutes=args.idle_minutes,
    )

    def watchdog() -> None:
        while True:
            time.sleep(5)
            job = server.current_job
            active = bool(job) and server.job_status(job) == "running"
            if not active and time.monotonic() - server.last_request > server.idle_seconds:
                server.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
