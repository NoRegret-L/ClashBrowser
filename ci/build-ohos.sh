#!/usr/bin/env bash
set -euo pipefail

flutter --version
sdk_version="$(jq -er '.data.platformVersion' "$DEVECO_SDK_HOME/default/sdk-pkg.json")"
test "$sdk_version" = "26.0.0"

if [[ ! -d ohos ]]; then
  flutter create --no-pub --platforms=ohos --project-name=clashbrowser --org io.github.noregretl .
fi

profile=ohos/build-profile.json5
if ! grep -q '"compileSdkVersion"' "$profile"; then
  # Template is JSON5; preserve trailing commas and comments.
  export COMPILE_SDK_VERSION="$sdk_version"
  perl -0pi -e 's{("compatibleSdkVersion"\s*:\s*"[^"]*",)}{"compileSdkVersion": "$ENV{COMPILE_SDK_VERSION}",\n        $1}g' "$profile"
fi
grep -Eq '"compileSdkVersion"\s*:\s*"26\.0\.0"' "$profile"

# Stable application identity; no signing material or network configuration.
perl -0pi -e 's/("bundleName"\s*:\s*")[^"]*(")/$1io.github.noregretl.clashbrowser$2/' ohos/AppScope/app.json5
grep -F '"io.github.noregretl.clashbrowser"' ohos/AppScope/app.json5

if [[ "${CLASHBROWSER_EMBED_OHOS:-0}" == 1 ]]; then
  mkdir -p ohos/entry/libs/arm64-v8a
  install -m 0644 sdk-input/libclash.so ohos/entry/libs/arm64-v8a/libclash.so
fi

if [[ "${CLASHBROWSER_EMBED_OHOS:-0}" == 1 ]]; then
  module=ohos/entry/src/main/module.json5
  if ! grep -q 'ohos.permission.INTERNET' "$module"; then
    if grep -Eq '"requestPermissions"\s*:' "$module"; then
      perl -0pi -e 's/("requestPermissions"\s*:\s*\[)/$1\n      {"name":"ohos.permission.INTERNET"},/' "$module"
    else
      perl -0pi -e 's/("module"\s*:\s*\{)/$1\n    "requestPermissions":[{"name":"ohos.permission.INTERNET"}],/' "$module"
    fi
  fi
  grep -F 'ohos.permission.INTERNET' "$module"
  ets=ohos/entry/src/main/ets
  cp native/ohos/BrowserPlugin.ets "$ets/entryability/"
  cp native/ohos/ohos_view.dart.in lib/core/ohos_view.dart
  entry="$ets/entryability/EntryAbility.ets"
  if ! grep -Fq 'new BrowserPlugin()' "$entry"; then
    grep -Fq 'GeneratedPluginRegistrant.registerWith(flutterEngine)' "$entry"
    perl -0pi -e 's/\A/import { BrowserPlugin } from ".\/BrowserPlugin";\n/; s/(GeneratedPluginRegistrant\.registerWith\(flutterEngine\));?/$1;\n    this.addPlugin(new BrowserPlugin());/' "$entry"
  fi
  grep -Fq 'new BrowserPlugin()' "$entry"
fi
rm -f analysis_options.yaml
flutter pub get
flutter analyze --no-pub lib test
flutter test --no-pub
# When embedded CI has no explicit override, compile both variants in the
# same generated project/container and reuse the native library and Pub graph.
# Explicit true/false remains a single-variant local build.
experimental_js="${CLASHBROWSER_OHOS_EXPERIMENTAL_JS:-auto}"
case "$experimental_js" in auto|true|false) ;; *) echo "Invalid experimental JS flag" >&2; exit 2 ;; esac
shopt -s nullglob
build_variant() {
  local flag="$1"
  flutter build hap --no-pub --debug --no-codesign --target-platform=ohos-arm64 \
    --dart-define="CLASHBROWSER_OHOS_EXPERIMENTAL_JS=$flag"
  haps=(build/ohos/hap/*-unsigned.hap)
  [[ "${#haps[@]}" -eq 1 ]]
  test -s "${haps[0]}"
  unzip -tq "${haps[0]}"
  ls -lh "${haps[0]}"
}
if [[ "$experimental_js" == auto && "${CLASHBROWSER_EMBED_OHOS:-0}" == 1 ]]; then
  build_variant false
  baseline="${haps[0]}"
  mkdir -p dist/native-app
  saved="$(mktemp)"
  trap 'rm -f "$saved"' EXIT
  cp "$baseline" "$saved"
  build_variant true
  cp "${haps[0]}" dist/native-app/clashbrowser-experimental-js.hap
  # Verify the second variant independently; it must not overwrite baseline.
  unzip -Z1 dist/native-app/clashbrowser-experimental-js.hap > dist/native-app/experimental-hap-list.txt
  grep -E '(^|/)libclash\.so$' dist/native-app/experimental-hap-list.txt
  cp "$saved" "$baseline"
  unzip -tq "$baseline"
  sha256sum "$baseline" dist/native-app/clashbrowser-experimental-js.hap
  # Reject identical outputs (e.g. tool ignored the Dart flag).
  if cmp -s "$saved" dist/native-app/clashbrowser-experimental-js.hap; then
    echo "Experimental and static HAPs are identical" >&2; exit 1
  fi
else
  [[ "$experimental_js" != auto ]] || experimental_js=false
  build_variant "$experimental_js"
fi
