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
cd "$project"
flutter pub get
flutter test --no-pub integration_test/proxy_device_test.dart -d emulator-5554
