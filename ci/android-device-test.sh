#!/usr/bin/env bash
set -euo pipefail
project="$1"
sdk="$2"
CLASHBROWSER_PREPARE_ONLY=1 bash ci/embed-mobile.sh android "$sdk" "$project"
mkdir -p "$project/integration_test"
cp integration_test/proxy_device_test.dart "$project/integration_test/"
python3 - "$project/pubspec.yaml" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
assert "dev_dependencies:" in s
p.write_text(s.replace("dev_dependencies:", "dev_dependencies:\n  integration_test:\n    sdk: flutter", 1))
PY
# Ephemeral CA and server key: never committed or bundled in a normal APK.
fixture="$(mktemp -d)"
fixture_pid=""
proxy_port=""
cleanup() {
  if [[ -n "$proxy_port" ]]; then adb -s emulator-5554 reverse --remove "tcp:$proxy_port" || true; fi
  if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; fi
  rm -rf "$fixture"
}
trap cleanup EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=ClashBrowser ephemeral integration CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$fixture/ca.key" -out "$fixture/ca.pem" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes \
  -subj '/CN=browser-tls-probe.invalid' \
  -keyout "$fixture/server.key" -out "$fixture/server.csr" >/dev/null 2>&1
cat > "$fixture/extensions" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:browser-tls-probe.invalid
EOF
openssl x509 -req -in "$fixture/server.csr" -CA "$fixture/ca.pem" \
  -CAkey "$fixture/ca.key" -CAcreateserial -days 1 \
  -extfile "$fixture/extensions" -out "$fixture/server.pem" >/dev/null 2>&1

debug="$project/android/app/src/debug"
mkdir -p "$debug/res/raw" "$debug/res/xml"
cp "$fixture/ca.pem" "$debug/res/raw/integration_ca.pem"
cat > "$debug/res/xml/integration_network_security.xml" <<'EOF'
<network-security-config>
  <domain-config cleartextTrafficPermitted="false">
    <domain includeSubdomains="false">browser-tls-probe.invalid</domain>
    <trust-anchors>
      <certificates src="system"/>
      <certificates src="@raw/integration_ca"/>
    </trust-anchors>
  </domain-config>
</network-security-config>
EOF
python3 - "$debug/AndroidManifest.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
p = sys.argv[1]
ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ns)
tree = ET.parse(p)
root = tree.getroot()
app = root.find('application')
if app is None:
    app = ET.SubElement(root, 'application')
app.set('{' + ns + '}networkSecurityConfig', '@xml/integration_network_security')
tree.write(p, encoding='unicode')
PY
python3 ci/https-fixture.py "$fixture" &
fixture_pid=$!
for _ in $(seq 1 50); do
  if [[ -s "$fixture/port" ]]; then break; fi
  kill -0 "$fixture_pid"
  sleep 0.1
done
proxy_port="$(cat "$fixture/port")"
adb -s emulator-5554 reverse "tcp:$proxy_port" "tcp:$proxy_port"
cd "$project"
flutter pub get
flutter analyze --no-pub integration_test
flutter test --no-pub integration_test/proxy_device_test.dart \
  -d emulator-5554 --dart-define="TEST_PROXY_PORT=$proxy_port"

# Verify actual server receipt, independent of WebView error callbacks.
python3 - "$fixture/events.jsonl" <<'PY'
import json, pathlib, sys
events = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(e == {"kind": "connect", "value": "browser-tls-probe.invalid:443"} for e in events), events
assert any(e == {"kind": "https", "value": "/verified"} for e in events), events
assert not any(e == {"kind": "connect", "value": "browser-blocked-probe.invalid:443"} for e in events), events
print("Authenticated CONNECT, TLS origin receipt and default REJECT verified")
PY
