"""Reuse a specific successful SDK build only if its source/build steps match."""
import os
import pathlib
import re
import subprocess
import sys

BASE = "f228efaaf748f5af7b65d5344286756c070ac128"
WORKFLOW = ".github/workflows/core.yml"
platform = sys.argv[1]
assert platform in ("android", "ios", "harmonyos")

def build_steps(text, cached):
    job = re.split(r"(?m)^  " + platform + r":\s*$", text, maxsplit=1)[1]
    job = re.split(r"(?m)^  [a-z][a-z-]*:\s*$", job, maxsplit=1)[0]
    anchor = "      - uses: actions/checkout@v4\n"
    # Second checkout is the pinned upstream; first is our repository.
    if cached:
        start = job.index(anchor, job.index("      - name: Remove unusable seed"))
        end = job.index("      - name: Verify cached or newly built SDK", start)
        block = job[start:end]
        block = re.sub(r"(?m)^        if: steps\.sdk-cache\.outputs\.cache-hit != 'true' && steps\.seed-verify\.outcome != 'success'\n", "", block)
    else:
        first = job.index(anchor)
        start = job.index(anchor, first + len(anchor))
        end = job.index("      - uses: actions/upload-artifact@v4", start)
        block = job[start:end]
    return block.strip()

match = False
try:
    same_source = subprocess.run(
        ["git", "diff", "--quiet", BASE, "HEAD", "--", "core", "ci/install-loopback.sh"],
        check=False,
    ).returncode == 0
    old = subprocess.check_output(["git", "show", BASE + ":" + WORKFLOW], text=True)
    current = pathlib.Path(WORKFLOW).read_text()
    match = same_source and build_steps(old, False) == build_steps(current, True)
except (ValueError, IndexError, OSError, subprocess.SubprocessError):
    pass
print("Verified previous SDK build steps and source match:", match)
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    output.write("match=" + str(match).lower() + "\n")
