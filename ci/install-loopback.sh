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
mkdir -p "$module/browserloop"
for f in loopback.go loopback_test.go; do
 if [[ "$platform" == ios || "$platform" == host ]]; then
  sed 's@github.com/metacubex/mihomo@github.com/ProjectClash/Clash@g' "core/loopback/$f" > "$module/browserloop/$f"
 else
  cp "core/loopback/$f" "$module/browserloop/"
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
