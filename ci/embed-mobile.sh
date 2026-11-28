#!/usr/bin/env bash
set -euo pipefail
platform="$1"
sdk="$2"
project="$3"
root="$PWD"
mkdir -p dist/native-app
if [[ "$platform" == ios ]]; then
  (cd "$sdk" && shasum -a 256 -c SHA256SUMS)
else
  (cd "$sdk" && sha256sum -c SHA256SUMS)
fi
flutter create --no-pub --project-name clashbrowser --org io.github.noregretl --platforms="$platform" "$project"
cp pubspec.yaml "$project/"
cp -R assets "$project/"
cp -R lib/. "$project/lib/"
cp -R test/. "$project/test/"
rm -f "$project/analysis_options.yaml"

if [[ "$platform" == android ]]; then
  manifest="$project/android/app/src/main/AndroidManifest.xml"
  if ! grep -q 'android.permission.INTERNET' "$manifest"; then
    python3 - "$manifest" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
p.write_text(s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',1))
PY
  fi
  # Inject only into the embedded app; no VPN service or global proxy.
  cp native/android/MainActivity.kt "$project/android/app/src/main/kotlin/io/github/noregretl/clashbrowser/MainActivity.kt"
  printf '\ndependencies { implementation("androidx.webkit:webkit:1.14.0") }\n' >> "$project/android/app/build.gradle.kts"
  libs="$project/android/app/src/main/jniLibs"
  mkdir -p "$libs"
  python3 - "$sdk" "$libs" <<'PY'
import pathlib
import sys
import zipfile
source, target = map(pathlib.Path, sys.argv[1:])
aar, = source.glob("*.aar")
with zipfile.ZipFile(aar) as z:
    for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
        directory = target / abi
        directory.mkdir()
        for lib in ("libclash.so", "libmihomo-jni.so"):
            (directory / lib).write_bytes(z.read(f"jni/{abi}/{lib}"))
PY
  if [[ "${CLASHBROWSER_PREPARE_ONLY:-0}" == 1 ]]; then
    exit 0
  fi
  cd "$project"
  flutter pub get
  flutter analyze --no-pub
  flutter test --no-pub
  flutter build apk --no-pub --debug
  cp build/app/outputs/flutter-apk/app-debug.apk "$root/dist/native-app/"
  unzip -Z1 "$root/dist/native-app/app-debug.apk" > "$project/apk-files"
  for abi in arm64-v8a armeabi-v7a x86_64; do
    grep -Fx "lib/$abi/libclash.so" "$project/apk-files"
    grep -Fx "lib/$abi/libmihomo-jni.so" "$project/apk-files"
  done
elif [[ "$platform" == ios ]]; then
  mkdir -p "$project/native"
  cp -R native/ios_probe "$project/native/"
  frameworks="$project/native/ios_probe/ios/Frameworks"
  mkdir -p "$frameworks"
  ditto -x -k "$sdk/Clash.xcframework.zip" "$frameworks"
  cp "$sdk/LICENSE" "$frameworks/"
  test -d "$frameworks/Clash.xcframework"
  # Add the platform-only plugin to this native build, not the offline baseline.
  python3 - "$project" <<'PY'
import pathlib
import re
import sys
root = pathlib.Path(sys.argv[1])
p = root / "pubspec.yaml"
text = p.read_text()
assert "dev_dependencies:" in text
p.write_text(text.replace("dev_dependencies:", "  clashbrowser_ios_probe:\n    path: native/ios_probe\ndev_dependencies:", 1))
p = root / "ios/Runner.xcodeproj/project.pbxproj"
text = p.read_text()
text, n = re.subn(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;', text)
assert n > 0
p.write_text(text)
pod = root / "ios/Podfile"
if pod.exists():
    text = pod.read_text()
    text, n = re.subn(r"(?m)^#?\s*platform :ios, ['\"][\d.]+['\"]", "platform :ios, '17.0'", text)
    if n == 0:
        text = "platform :ios, '17.0'\n" + text
    pod.write_text(text)
PY
  cd "$project"
  flutter pub get
  flutter analyze --no-pub
  flutter test --no-pub
  flutter build ios --no-pub --release --no-codesign
  test -s build/ios/iphoneos/Runner.app/Runner
  ditto -c -k --keepParent build/ios/iphoneos/Runner.app "$root/dist/native-app/ios-unsigned.zip"
else
  echo "Unsupported platform" >&2
  exit 1
fi
