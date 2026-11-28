# Incremental CI (P0)

Fast Dart feedback is an early signal, never a substitute for the existing Mihomo native SDK workflow. The existing three native SDK jobs, host routing and real HTTP/CONNECT tests, embedded apps and Android emulator test still run. The separate rule and isolation workflows remain intact. The core workflow now also triggers for rules, assets, integration tests, lockfile and all CI scripts.

SDK keys use SHA-256 over the selected platform job, workflow-wide header, all tracked core files and the install/seed/fingerprint scripts. Changes in another job do not invalidate an otherwise identical SDK. Shared source changes invalidate every SDK. Unknown workflow layouts conservatively hash the entire workflow. The existing exact-match verified seed and checksum checks remain in place; v2 cache keys may require one cold build. A cache miss is not a test pass.

The Android embedded build now uses the same Gradle cache action as the emulator, and the fast Dart check restores Flutter and pub dependencies. No third-party mirrors, trust changes, skipped tests, or retry-until-pass logic are added.

Review CI timings on comparable cold and warm runs before claiming a speedup. GitHub cache branch scope can prevent reuse across unrelated PRs. Full rule conversion remains in host routing until a separate, verified rule artifact reuse design is proven. Device isolation and release checks remain mandatory; this PR does not configure repository branch protection or claim physical-device evidence.
