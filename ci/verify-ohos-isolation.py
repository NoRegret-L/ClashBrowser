#!/usr/bin/env python3
"""Offline, narrowly scoped device evidence verifier; never contacts the network."""
import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

def addresses(values):
    if not isinstance(values, list) or not values:
        raise ValueError("provide a nonempty address list")
    return {str(ipaddress.ip_address(v)) for v in values}

def address_filter(values, direction):
    terms = []
    for v in sorted(addresses(values)):
        prefix = "ipv6" if ":" in v else "ip"
        terms.append(f"{prefix}.{direction} == {v}")
    return "(" + " || ".join(terms) + ")"

def packet_count(path, expression):
    # -n disables name resolution. Filters contain only validated literal IPs.
    result = subprocess.run(
        ["tshark", "-n", "-r", str(path), "-Y", expression,
         "-T", "fields", "-e", "frame.number"],
        check=True, capture_output=True, text=True)
    return sum(bool(line.strip()) for line in result.stdout.splitlines())

def dns_queries(path, source):
    result = subprocess.run(
        ["tshark", "-n", "-r", str(path),
         "-Y", source + " && dns.flags.response == 0 && dns.qry.name",
         "-T", "fields", "-e", "dns.qry.name", "-E", "occurrence=a",
         "-E", "aggregator=,"],
        check=True, capture_output=True, text=True)
    return {name.lower().rstrip(".") for line in result.stdout.splitlines()
            for name in line.split(",") if name}

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def inspect_events(path, run, allowed, blocked, peer):
    records = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
               if line.strip()]
    relevant = [r for r in records if r.get("run") == run]
    kinds = {r["kind"] for r in relevant}
    failures, missing = [], []
    for r in relevant:
        if r["kind"] == "blocked-received":
            failures.append("blocked origin received HTTP request")
        if r["host"] == allowed and r["peer"] not in peer:
            failures.append("allowed origin event has unexpected source IP")
        if r["host"] not in {allowed, blocked}:
            failures.append("unexpected host in event record")
    if kinds & {"sw-registered", "worker-received"}:
        failures.append("Service Worker registration or script request observed")
    if kinds & {"blocked-ok", "fetch-error"}:
        failures.append("browser reported unexpected fetch outcome")
    for kind in {"js", "fetch-ok", "fetch-received", "blocked-error"} - kinds:
        missing.append("missing event " + kind)
    if not kinds & {"sw-denied", "sw-unavailable"}:
        missing.append("missing Service Worker negative result")
    # No ICE attempt is not a positive test of UDP enforcement.
    if not {"ice-start", "ice-complete"} <= kinds:
        missing.append("ICE execution/completion not observed")
    return failures, missing

def inspect_counts(control, trial):
    failures, missing = [], []
    for key in ("device", "proxy"):
        if trial[key] == 0:
            missing.append(f"trial capture has no {key} traffic")
    for key in ("stun", "blocked", "origin"):
        if trial[key] != 0:
            failures.append(f"direct {key} packets: {trial[key]}")
        if control[key] == 0:
            missing.append(f"positive control did not observe direct {key} traffic")
    return failures, missing

def domain(name):
    if not isinstance(name, str) or not re.fullmatch(
        r"(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+",
        name.lower()):
        raise ValueError("invalid owned hostname")
    return name.lower()

def counts(path, cfg):
    src = address_filter(cfg["device_ips"], "src")
    def flow(ips, extra=""):
        return packet_count(path, src + " && " + address_filter(ips, "dst") + extra)
    return {
        "device": packet_count(path, src),
        "proxy": flow(cfg["proxy_ips"]),
        "stun": flow(cfg["stun_ips"], " && udp"),
        "blocked": flow(cfg["blocked_ips"]),
        "origin": flow(cfg["origin_ips"]),
    }

def verify(manifest_path):
    cfg = json.loads(manifest_path.read_text(encoding="utf-8"))
    run = str(uuid.UUID(cfg["run"]))
    allowed, blocked, stun = (domain(cfg[k]) for k in ("allowed_host", "blocked_host", "stun_host"))
    if len({allowed, blocked, stun}) != 3 or any(
        x.endswith("." + allowed) for x in (blocked, stun)):
        raise ValueError("distinct owned names outside allowed suffix required")
    groups = {k: addresses(cfg[k]) for k in
              ("device_ips", "proxy_ips", "origin_ips", "blocked_ips", "stun_ips", "proxy_egress_ips")}
    # Sharing an IP with the proxy makes direct-vs-proxy classification ambiguous.
    for k in ("device_ips", "origin_ips", "blocked_ips", "stun_ips"):
        if groups["proxy_ips"] & groups[k]:
            raise ValueError(f"proxy and {k} IP sets overlap")
    if groups["proxy_egress_ips"] & groups["device_ips"]:
        raise ValueError("ambiguous proxy egress identity")
    paths = {k: (manifest_path.parent / cfg[k]).resolve() for k in
             ("control_pcap", "trial_pcap", "events")}
    if len(set(paths.values())) != 3 or any(not p.is_file() or not p.stat().st_size for p in paths.values()):
        raise ValueError("provide three distinct nonempty evidence files")
    hashes = {k: digest(p) for k, p in paths.items()}
    if hashes["control_pcap"] == hashes["trial_pcap"]:
        raise ValueError("control and trial capture are identical")
    control = counts(paths["control_pcap"], cfg)
    trial = counts(paths["trial_pcap"], cfg)
    failures, missing = inspect_counts(control, trial)
    ef, em = inspect_events(paths["events"], run, allowed, blocked, groups["proxy_egress_ips"])
    failures += ef
    missing += em
    queried = dns_queries(paths["trial_pcap"], address_filter(cfg["device_ips"], "src"))
    # DNS case folding and trailing-dot normalization above. No unrelated names
    # are emitted in the report. Encrypted DNS requires separate inspection.
    for name in (allowed, blocked, stun):
        if name in queried:
            failures.append("plaintext device DNS query: " + name)
    if cfg.get("capture_complete") is not True:
        missing.append("operator did not attest full pre-NAT IPv4/IPv6 capture and positive control")
    status = "FAIL" if failures else ("INCONCLUSIVE" if missing else "PASS_SCOPED")
    return {"status": status, "run": run, "hashes": hashes, "positive_control": control,
            "experimental": trial, "failures": failures, "missing": missing,
            "limits": ["No claim about encrypted DNS, unspecified destinations, OS background traffic,"
                       " proxy-stop/other-app behavior, or device-wide isolation.",
                       "Capture completeness and IP provenance require operator verification."]}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("manifest", type=Path)
    a = p.parse_args()
    try:
        result = verify(a.manifest)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        print(json.dumps({"status": "INCONCLUSIVE", "error": str(exc)}))
        return 2
    print(json.dumps(result, indent=2))
    return {"PASS_SCOPED": 0, "FAIL": 1, "INCONCLUSIVE": 2}[result["status"]]

if __name__ == "__main__":
    sys.exit(main())
