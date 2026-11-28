"""Install a read-only callback at the existing native match result.
Fail if the pinned upstream anchor changes; never edit the global Go cache.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
prefix = sys.argv[2]
path = root / "tunnel/tunnel.go"
source = path.read_text()
pattern = r"(?m)^([ \t]*)proxy, rule, err = match\(metadata, helper(?:, version)?\)[ \t]*$"
def insert(m):
    return m[0] + "\n" + m[1] + "clashBrowserNotifyRoute(metadata, proxy, rule, err)"
source, count = re.subn(pattern, insert, source)
if count != 1:
    raise SystemExit(f"Expected exactly one native match anchor, found {count}")
target = root / "tunnel/clashbrowser_observer.go"
if target.exists():
    raise SystemExit("Observer already installed")
template = Path(__file__).with_name("observer.go.in").read_text()
target.write_text(template.replace("MODULE_PREFIX", prefix))
path.write_text(source)
