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

rm -f analysis_options.yaml
flutter pub get
flutter analyze lib test
flutter test
flutter build hap --debug --no-codesign --target-platform=ohos-arm64

# The upstream Flutter tool copies the unsigned package here on success.
# Do not report success on a signing warning or a failed command.
shopt -s nullglob
haps=(build/ohos/hap/*-unsigned.hap)
[[ "${#haps[@]}" -eq 1 ]]
test -s "${haps[0]}"
unzip -tq "${haps[0]}"
ls -lh "${haps[0]}"
