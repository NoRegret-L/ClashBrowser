#!/usr/bin/env python3
"""Build a reproducible local MRS bundle from the reviewed upstream snapshot."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
pin = json.loads((ROOT / "rules/snapshot.json").read_text())
binary, out = (Path(a).resolve() for a in sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
assets = out / "assets/rules"
assets.mkdir(parents=True, exist_ok=True)

def git(repo, *args, capture=False):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          stdout=subprocess.PIPE if capture else None).stdout

def checkout(repo, revision):
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "fetch", "--depth=1", pin["repository"], revision)
    git(repo, "checkout", "--detach", "FETCH_HEAD")
    assert git(repo, "rev-parse", "HEAD", capture=True).decode().strip() == revision

with tempfile.TemporaryDirectory() as td:
    data, license_repo = Path(td)/"data", Path(td)/"license"
    checkout(data, pin["revision"])
    checkout(license_repo, pin["licenseRevision"])
    (assets/"LICENSE-Loyalsoldier.txt").write_bytes((license_repo/"LICENSE").read_bytes())
    hashes = {}
    for name, behavior in pin["providers"].items():
        src = data / (name + ".txt")
        dest = assets / (name + ".mrs")
        assert src.is_file() and src.stat().st_size > 0
        subprocess.run([str(binary), "convert-ruleset", behavior, "yaml", str(src), str(dest)], check=True)
        assert dest.is_file() and dest.stat().st_size > 0, f"Missing {name}"
        hashes[dest.name] = hashlib.sha256(dest.read_bytes()).hexdigest()
        print(f"{name}: {src.stat().st_size} YAML bytes -> {dest.stat().st_size} MRS bytes")
    manifest = dict(revision=pin["revision"], converterRevision=pin["converterRevision"], files=hashes)
    (assets/"manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2)+"\n")
    # Retain original data and upstream license source for release review.
    git(data, "archive", "--format=tar.gz", "-o", str(out/"loyalsoldier-source.tar.gz"), "HEAD")
    (out/"snapshot.json").write_text(json.dumps(pin, sort_keys=True, indent=2)+"\n")
