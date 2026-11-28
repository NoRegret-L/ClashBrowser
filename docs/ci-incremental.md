# Incremental CI (P0)

Fast Dart feedback is an early signal, never a substitute for the existing Mihomo native SDK workflow. The existing three native SDK jobs, host routing and real HTTP/CONNECT tests, embedded apps and Android emulator test still run. The separate rule and isolation workflows remain intact. The core workflow now also triggers for rules, assets, integration tests, lockfile and all CI scripts.

SDK keys use SHA-256 over the selected platform job, workflow-wide header, all tracked core files and the install/seed/fingerprint scripts. Changes in another job do not invalidate an otherwise identical SDK. Shared source changes invalidate every SDK. Unknown workflow layouts conservatively hash the entire workflow. The existing exact-match verified seed and checksum checks remain in place; v2 cache keys may require one cold build. A cache miss is not a test pass.

The Android embedded build now uses the same Gradle cache action as the emulator, and the fast Dart check restores Flutter and pub dependencies. No third-party mirrors, trust changes, skipped tests, or retry-until-pass logic are added.

Review CI timings on comparable cold and warm runs before claiming a speedup. GitHub cache branch scope can prevent reuse across unrelated PRs. Full rule conversion remains in host routing until a separate, verified rule artifact reuse design is proven. Device isolation and release checks remain mandatory; this PR does not configure repository branch protection or claim physical-device evidence.

Each embedded application now waits only for its own SDK and host-routing rule artifact. The reusable native-app workflow retains the original build, provenance and artifact steps. Full native verification fails if any of the eight prerequisites is failed, cancelled or skipped. The HarmonyOS Docker cache configuration is unchanged pending warm/cold evidence. Existing check names may change for called workflows; review branch protection before making the new aggregate gate required.

### Cold PR Docker cache and Android device startup

The pinned single-stage OHOS Dockerfile already uses final-layer cache. In PR #4 a cold build exported a 2.32 GB SDK layer and other layers, consuming 281.1 s. PR caches are isolated from unrelated PRs. Restrict export to main and feat/mobile-bootstrap pushes, while every PR retains cache imports and the same pinned Docker build plus both HAP variants. Development pushes now run core CI to seed shared base caches. First cold PR can still be slow; compare later warm runs. No mutable image tag or registry trust is introduced.

PR #4's emulator installed its APK but timed out before any fixture event. Provision the Flutter template's observed NDK/CMake versions before boot, check ADB reverse mapping, and add non-secret lifecycle checkpoints and failure diagnostics. Keep the original watchdog, test assertions and required fixture evidence. The root cause is not yet proven; do not merge until the real test passes.
