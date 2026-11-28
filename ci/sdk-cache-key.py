#!/usr/bin/env python3
"""Conservative content-addressed SDK cache keys for the checked-out commit."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ".github/workflows/core.yml"
PLATFORMS = ("android", "ios", "harmonyos")
INPUTS = ("core", "ci/install-loopback.sh", "ci/seed-sdk.py", "ci/sdk-cache-key.py")


def workflow_input(text, platform):
    # Keep all workflow-wide settings; isolate only the selected job. If the
    # established indentation/layout changes, fall back to the full workflow.
    marker = re.search(r"(?m)^jobs:[ \t]*\n", text)
    if not marker or platform not in PLATFORMS:
        return text
    jobs = text[marker.end():]
    trailing = re.search(r"(?m)^[A-Za-z_][A-Za-z0-9_-]*:", jobs)
    if trailing:
        return text
    starts = list(re.finditer(r"(?m)^  ([A-Za-z_][A-Za-z0-9_-]*):[ \t]*\n", jobs))
    names = [m.group(1) for m in starts]
    if names.count(platform) != 1 or not all(p in names for p in PLATFORMS):
        return text
    if jobs[:starts[0].start()].strip():
        return text
    i = names.index(platform)
    end = starts[i + 1].start() if i + 1 < len(starts) else len(jobs)
    return text[:marker.end()] + jobs[starts[i].start():end]


def digest(platform):
    h = hashlib.sha256()
    def add(data):
        h.update(len(data).to_bytes(8, "big"))
        h.update(data)
    add(platform.encode())
    add(workflow_input((ROOT / WORKFLOW).read_text(), platform).encode())
    # Git index records include path, executable mode and blob ID. Also hash
    # actual bytes so untracked mutations of tracked files cannot alias a key.
    records = subprocess.check_output(
        ["git", "ls-files", "-s", "-z", "--", *INPUTS], cwd=ROOT
    ).split(b"\0")
    found = set()
    for record in sorted(r for r in records if r):
        metadata, name = record.split(b"\t", 1)
        mode, _, stage = metadata.split()
        if stage != b"0" or mode not in (b"100644", b"100755"):
            raise ValueError("Unexpected SDK input mode or unresolved index entry")
        path = os.fsdecode(name)
        found.add(path)
        add(record)
        add((ROOT / path).read_bytes())
    if not all(p in found for p in INPUTS[1:]) or not any(p.startswith("core/") for p in found):
        raise ValueError("Incomplete SDK input set")
    return h.hexdigest()


class CacheKeyTests(unittest.TestCase):
    def test_unrelated_job_does_not_invalidate(self):
        text = "name: SDK\njobs:\n  android:\n    runs-on: linux\n  ios:\n    runs-on: mac\n  harmonyos:\n    runs-on: linux\n  native-app:\n    timeout-minutes: 20\n"
        changed = text.replace("timeout-minutes: 20", "timeout-minutes: 30")
        self.assertEqual(workflow_input(text, "android"), workflow_input(changed, "android"))
        self.assertNotEqual(workflow_input(text, "android"), workflow_input(text.replace("runs-on: linux", "runs-on: new", 1), "android"))
        self.assertNotEqual(workflow_input(text, "android"), workflow_input(text.replace("name: SDK", "name: new"), "android"))

    def test_other_platform_isolated(self):
        text = "jobs:\n  android:\n    runs-on: linux\n  ios:\n    runs-on: mac\n  harmonyos:\n    runs-on: linux\n"
        changed = text.replace("runs-on: mac", "runs-on: mac-new")
        self.assertEqual(workflow_input(text, "android"), workflow_input(changed, "android"))
        self.assertNotEqual(workflow_input(text, "ios"), workflow_input(changed, "ios"))

    def test_unknown_layout_uses_whole_workflow(self):
        text = "jobs:\n    android:\n      runs-on: linux\n"
        self.assertEqual(workflow_input(text, "android"), text)
        text = "jobs:\n  android:\n    runs-on: linux\n  ios:\n    runs-on: mac\n  harmonyos:\n    runs-on: linux\nenv:\n  FLAG: value\n"
        self.assertEqual(workflow_input(text, "android"), text)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        unittest.main(argv=[sys.argv[0]])
    elif len(sys.argv) == 2 and sys.argv[1] in PLATFORMS:
        value = digest(sys.argv[1])
        print(f"SDK input digest: {value}")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"digest={value}\n")
    else:
        raise SystemExit("Usage: sdk-cache-key.py android|ios|harmonyos|--self-test")
