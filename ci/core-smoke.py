"""Real core regression: loopback-only listener, DIRECT, proxy and REJECT.

The JSON fixture is also valid YAML. All traffic remains on the CI runner.
No external services, real credentials or VPN are required.
"""
import base64
import contextlib
import http.client
import http.server
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time


class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"direct-origin"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class Upstream(http.server.BaseHTTPRequestHandler):
    def do_CONNECT(self):
        if self.path != "proxied.invalid:80":
            self.send_error(400)
            return
        self.send_response(200, "Connection established")
        self.end_headers()
        self.wfile.flush()
        request = self.rfile.readline()
        if not request.startswith(b"GET "):
            raise AssertionError("Expected HTTP request through CONNECT")
        while self.rfile.readline().strip():
            pass
        body = b"proxied-origin"
        self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Length: " +
                         str(len(body)).encode() +
                         b"\r\nConnection: close\r\n\r\n" + body)
        self.wfile.flush()

    def log_message(self, *_):
        pass


@contextlib.contextmanager
def serving(handler):
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield server.server_port
        finally:
            server.shutdown()
            worker.join()


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def request(port, url):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request("GET", url)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def main(binary):
    with serving(Origin) as origin, serving(Upstream) as upstream, tempfile.TemporaryDirectory() as home:
        port = free_port()
        cfg = {
            "mixed-port": port,
            "bind-address": "127.0.0.1",
            "allow-lan": False,
            "mode": "rule",
            "log-level": "warning",
            "ipv6": False,
            "find-process-mode": "off",
            "tun": {"enable": False},
            "dns": {"enable": False},
            "proxies": [{"name": "TEST-PROXY", "type": "http", "server": "127.0.0.1", "port": upstream}],
            "rules": [
                "DOMAIN,proxied.invalid,TEST-PROXY",
                "IP-CIDR,127.0.0.1/32,DIRECT,no-resolve",
                "MATCH,REJECT",
            ],
        }
        encoded = base64.b64encode(json.dumps(cfg).encode()).decode()
        # Avoid inherited CLASH override variables, including scripts or controllers.
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLASH_")}
        command = [binary, "-d", home, "-config", encoded]
        subprocess.run(command + ["-t"], check=True, timeout=30, env=env)
        with tempfile.TemporaryFile(mode="w+b") as logs:
            process = subprocess.Popen(command, stdout=logs, stderr=subprocess.STDOUT, env=env)
            try:
                deadline = time.monotonic() + 20
                while True:
                    if process.poll() is not None:
                        raise AssertionError("Core exited before listener readiness")
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=1):
                            break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(0.1)
                assert request(port, f"http://127.0.0.1:{origin}/") == (200, b"direct-origin")
                print("PASS: explicit DIRECT")
                assert request(port, "http://proxied.invalid/") == (200, b"proxied-origin")
                print("PASS: rule selected the upstream HTTP proxy through CONNECT")
                try:
                    status, _ = request(port, "http://blocked.invalid/")
                except (OSError, http.client.HTTPException):
                    pass
                else:
                    assert status >= 400, "REJECT unexpectedly returned success"
                print("PASS: default REJECT")
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                logs.seek(0)
                print(logs.read().decode(errors="replace"))
            try:
                request(port, f"http://127.0.0.1:{origin}/")
            except OSError:
                print("PASS: stopped listener does not provide implicit direct fallback")
            else:
                raise AssertionError("Listener unexpectedly remained accessible")


if __name__ == "__main__":
    main(sys.argv[1])
