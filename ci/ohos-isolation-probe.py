#!/usr/bin/env python3
"""Controlled HTTPS origin for HarmonyOS device tests; no third-party probes."""
import argparse
import http.server
import json
import re
import ssl
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

HOST = re.compile(r"(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$")
RUN = re.compile(r"[a-f0-9-]{36}")
EVENTS = {"js", "fetch-ok", "fetch-error", "blocked-ok", "blocked-error",
          "sw-unavailable", "sw-denied", "sw-registered",
          "ice-start", "ice-complete", "ice-error", "ice-unavailable",
          "candidate-host", "candidate-srflx", "candidate-relay", "candidate-prflx"}
PAGE = """<!doctype html><meta charset="utf-8"><title>ClashBrowser isolation probe</title>
<h1>ClashBrowser isolation probe</h1><p id="state">STATIC: JavaScript has not run</p>
<p>Use only on the controlled test network. Start capture before pressing Run.</p>
<button id="run" disabled>Run network probes</button><button id="stop" disabled>Stop ICE</button>
<pre id="output"></pre><script src="/probe.js"></script>"""
SCRIPT = r"""
'use strict';
const config = __CONFIG__;
const run = crypto.randomUUID();
const output = document.getElementById('output');
const state = document.getElementById('state');
const button = document.getElementById('run');
const stop = document.getElementById('stop');
let peer;
function note(event) {
  output.textContent += event + '\n';
  // Controlled same-origin event receipt, not the authority for leakage claims.
  fetch('/event?run=' + run + '&event=' + event,
        {cache:'no-store', credentials:'omit'}).catch(() => {});
}
state.textContent = 'JavaScript executed — run ' + run;
button.disabled = false;
note('js');
async function requests() {
  try {
    const res = await fetch('/fetch?run=' + run, {cache:'no-store'});
    note(res.ok && await res.text() === run ? 'fetch-ok' : 'fetch-error');
  } catch (_) { note('fetch-error'); }
  try {
    await fetch(config.blocked + '/blocked?run=' + run,
      {mode:'no-cors',cache:'no-store',credentials:'omit'});
    note('blocked-ok');
  } catch (_) { note('blocked-error'); }
}
async function worker() {
  if (!('serviceWorker' in navigator)) { note('sw-unavailable'); return; }
  try {
    const registration = await navigator.serviceWorker.register('/sw.js?run=' + run);
    note('sw-registered');
    await registration.unregister();
  } catch (_) { note('sw-denied'); }
}
async function ice() {
  if (typeof RTCPeerConnection !== 'function') { note('ice-unavailable'); return; }
  try {
    peer = new RTCPeerConnection({iceServers: [{urls:config.stun}]});
    stop.disabled = false;
    peer.onicecandidate = e => {
      const type = e.candidate && e.candidate.type;
      if (['host','srflx','relay','prflx'].includes(type)) note('candidate-' + type);
    };
    peer.onicegatheringstatechange = () => {
      if (peer.iceGatheringState === 'complete') note('ice-complete');
    };
    peer.createDataChannel('isolation-probe');
    await peer.setLocalDescription(await peer.createOffer());
    note('ice-start');
  } catch (_) { note('ice-error'); }
}
button.onclick = () => {
  button.disabled = true;
  requests(); worker(); ice();
};
stop.onclick = () => {
  if (peer) peer.close();
  stop.disabled = true;
};
window.addEventListener('pagehide', () => { if (peer) peer.close(); });
"""

def domain(value):
    value = value.lower()
    if not HOST.fullmatch(value) or not any(c.isalpha() for c in value):
        raise argparse.ArgumentTypeError("expected an owned DNS hostname")
    return value

def port(value):
    n = int(value)
    if not 1 <= n <= 65535:
        raise argparse.ArgumentTypeError("invalid port")
    return n

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bind", default="127.0.0.1")
    p.add_argument("--port", type=port, default=443)
    p.add_argument("--allowed", required=True, type=domain)
    p.add_argument("--blocked", required=True, type=domain)
    p.add_argument("--stun", required=True, type=domain)
    p.add_argument("--stun-port", type=port, default=3478)
    p.add_argument("--cert", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--events", required=True, type=Path)
    a = p.parse_args()
    if len({a.allowed, a.blocked, a.stun}) != 3:
        p.error("use distinct owned hostnames; configure only allowed in Mihomo")
    suffix = "" if a.port == 443 else ":" + str(a.port)
    config = {"blocked": "https://" + a.blocked + suffix,
              "stun": "stun:" + a.stun + ":" + str(a.stun_port)}
    lock = threading.Lock()
    script = SCRIPT.replace("__CONFIG__", json.dumps(config)).encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # no arbitrary URL or credential logging

        def do_GET(self):
            host = self.headers.get("Host", "").lower().split(":")[0]
            u = urlsplit(self.path)
            q = parse_qs(u.query)
            run = q.get("run", [""])[0]
            event = q.get("event", [""])[0]
            valid_run = bool(RUN.fullmatch(run))
            if host not in {a.allowed, a.blocked}:
                self.send_error(404)
                return
            body, mime, code, kind = b"", "text/plain", 404, ""
            if host == a.blocked and u.path == "/blocked" and valid_run:
                code, kind, body = 200, "blocked-received", b"UNEXPECTED"
            elif host == a.allowed:
                if u.path == "/":
                    code, kind, mime, body = 200, "page", "text/html", PAGE.encode()
                elif u.path == "/probe.js":
                    code, kind, mime, body = 200, "script", "application/javascript", script
                elif u.path == "/fetch" and valid_run:
                    code, kind, body = 200, "fetch-received", run.encode()
                elif u.path == "/sw.js" and valid_run:
                    code, kind, mime, body = 200, "worker-received", "application/javascript", b"// test worker"
                elif u.path == "/event" and valid_run and event in EVENTS:
                    code, kind = 200, event
            if kind:
                with lock, a.events.open("a", encoding="utf-8") as out:
                    # Peer is the transport source, not an X-Forwarded-For claim.
                    out.write(json.dumps({"kind": kind, "run": run if valid_run else "",
                                         "host": host, "peer": self.client_address[0]}) + "\n")
            self.send_response(code)
            self.send_header("Content-Type", mime + "; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy",
                             "default-src 'self'; connect-src 'self' " + config["blocked"] +
                             "; worker-src 'self'; object-src 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(body)

    with http.server.ThreadingHTTPServer((a.bind, a.port), Handler) as server:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(a.cert, a.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        print("Controlled probe ready; start gateway capture before opening the page", flush=True)
        server.serve_forever()

if __name__ == "__main__":
    main()
