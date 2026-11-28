"""Test-only HTTPS origin and CONNECT relay; never resolves public hosts."""
import http.server
import json
import pathlib
import selectors
import socket
import socketserver
import ssl
import sys
import threading

ROOT = pathlib.Path(sys.argv[1])
TARGET = "browser-tls-probe.invalid:443"
lock = threading.Lock()

def record(kind, value):
    with lock, (ROOT / "events.jsonl").open("a", encoding="utf-8") as out:
        out.write(json.dumps({"kind": kind, "value": value}) + "\n")

class Origin(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        record("https", self.path)
        # Record presence only; never log actual credentials.
        if self.headers.get("Authorization") or self.headers.get("Proxy-Authorization"):
            record("credential-leak", "origin-header")
            self.send_error(400)
            return
        if self.path == "/auth-required":
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm=""')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/start":
            self.send_response(302)
            self.send_header("Location", "/verified")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"<!doctype html><title>ClashBrowser TLS verified</title><h1>TLS verified</h1>"
        self.send_response(200 if self.path == "/verified" else 404)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(ROOT / "server.pem", ROOT / "server.key")
origin.socket = context.wrap_socket(origin.socket, server_side=True)

class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(10)
        header = bytearray()
        try:
            while not header.endswith(b"\r\n\r\n"):
                chunk = client.recv(1)
                if not chunk or len(header) >= 16384:
                    return
                header.extend(chunk)
            parts = header.split(b"\r\n", 1)[0].decode("ascii").split()
            if len(parts) != 3 or parts[0] != "CONNECT":
                return
            record("connect", parts[1])
            if parts[1] != TARGET:
                client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                return
            with socket.create_connection(("127.0.0.1", origin.server_port), timeout=10) as server:
                client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                with selectors.DefaultSelector() as sel:
                    sel.register(client, selectors.EVENT_READ, server)
                    sel.register(server, selectors.EVENT_READ, client)
                    while True:
                        events = sel.select(timeout=20)
                        if not events:
                            return
                        for key, _ in events:
                            data = key.fileobj.recv(65536)
                            if not data:
                                return
                            key.data.sendall(data)
        except (OSError, ValueError, UnicodeError):
            return

class Proxy(socketserver.ThreadingTCPServer):
    daemon_threads = True

with Proxy(("127.0.0.1", 0), Relay) as proxy:
    threading.Thread(target=origin.serve_forever, daemon=True).start()
    (ROOT / "port").write_text(str(proxy.server_address[1]))
    proxy.serve_forever()
