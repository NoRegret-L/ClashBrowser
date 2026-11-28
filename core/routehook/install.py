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

# The embedded SDK exposes only the authenticated browser listener. A 407
# received from an HTTP origin/upstream is not this listener's challenge.
# Preserve its own 407 outside the trusted forwarding branch and preserve
# normal origin 401 (including WWW-Authenticate).
proxy_path = root / "listener/http/proxy.go"
proxy_source = proxy_path.read_text()
anchor = "\t\t\tremoveHopByHopHeaders(resp.Header)"
if proxy_source.count(anchor) != 1:
    raise SystemExit("Expected exactly one forwarded HTTP response anchor")
replacement = """			if authenticator != nil && resp.StatusCode == http.StatusProxyAuthRequired {
				if resp.Body != nil {
					_ = resp.Body.Close()
				}
				resp = responseWith(request, http.StatusBadGateway)
				resp.Close = true
			}
			removeHopByHopHeaders(resp.Header)"""
proxy_path.write_text(proxy_source.replace(anchor, replacement, 1))
