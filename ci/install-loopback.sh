#!/usr/bin/env bash
set -euo pipefail
platform="$1"
root="$PWD"
case "$platform" in
 android) module=vendor/android/src/main/jni/core; prefix=github.com/oviron/libmihomo-android ;;
 harmonyos) module=vendor/arkclash/core; prefix=github.com/VOD-Studio/ArkClash/core ;;
 ios|host) module=vendor/apple; prefix=github.com/ProjectClash/Clash ;;
 *) exit 2 ;;
esac
# Install the same match-result observer in the three pinned native builds.
# Android uses a private copy of the downloaded dependency; ArkClash already
# creates and patches a private dependency tree for each ABI.
case "$platform" in
 android)
  (
   cd "$module"
   go mod download github.com/metacubex/mihomo
   dep="$(go list -m -f '{{.Dir}}' github.com/metacubex/mihomo)"
   target="$PWD/.clashbrowser-mihomo"
   test ! -e "$target"
   cp -R "$dep" "$target"
   chmod -R u+w "$target"
   python3 "$root/core/routehook/install.py" "$target" github.com/metacubex/mihomo
   go mod edit "-replace=github.com/metacubex/mihomo=$target"
  )
  ;;
 harmonyos)
  printf '\npython3 %q "$DEST" github.com/metacubex/mihomo\n' "$root/core/routehook/install.py" >> vendor/arkclash/scripts/prepare-mihomo.sh
  ;;
 ios|host)
  python3 "$root/core/routehook/install.py" "$module" github.com/ProjectClash/Clash
  ;;
esac
mkdir -p "$module/browserloop"
for source in core/loopback/*.go; do
 f="$(basename "$source")"
 if [[ "$platform" == ios || "$platform" == host ]]; then
  sed 's@github.com/metacubex/mihomo@github.com/ProjectClash/Clash@g' "$source" > "$module/browserloop/$f"
 else
  cp "$source" "$module/browserloop/"
 fi
done
if [[ "$platform" == android || "$platform" == harmonyos ]]; then
 cat > "$module/clashbrowser_loopback.go" <<EOF
package main
/*
#include <stdlib.h>
*/
import "C"
import (
 "unsafe"
 "$prefix/browserloop"
)
//export ClashBrowserLoopback
func ClashBrowserLoopback(s *C.char) *C.char { return C.CString(browserloop.Command(C.GoString(s))) }
//export ClashBrowserFree
func ClashBrowserFree(s *C.char) { C.free(unsafe.Pointer(s)) }
EOF
elif [[ "$platform" == ios ]]; then
 cat > "$module/bind/clash/browser_loopback.go" <<'EOF'
package clash
import "github.com/ProjectClash/Clash/browserloop"
func BrowserLoopback(input string) string { return bridgeSafeString(browserloop.Command(input)) }
EOF
fi
