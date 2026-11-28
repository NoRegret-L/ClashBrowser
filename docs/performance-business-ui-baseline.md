# P1–P3 acceptance baseline

## P1 performance

BrowserLibrary formerly serialized the whole history synchronously for every mutation and queued every snapshot for a separate flushed atomic rename. The single-writer dirty-state drain coalesces overlapping writes, without a timer or threshold. Sequential operations still await durable writes; overlapping callers wait for the same drain. Atomic rename, privacy sanitization, corrupted-file handling and explicit close/flush remain unchanged. Abrupt process death can still lose in-flight writes; this is not a durability improvement. The new synthetic 65-mutation test records elapsed microseconds, verifies a shared writer and restores the final state. No device latency or memory improvement is claimed before measurement.

The horizontal logical tab strip now lazily builds visible chips, retaining one active native renderer and existing close/recreate authentication handshake. Do not retain background WebViews or bypass close acknowledgement just for faster switching.

Device baseline: on a fixed device/OS, node and local TLS fixture, measure core startup, view readiness, successful navigation/redirect, tab switching, peak memory and frame timings. Use profile builds and Flutter DevTools/integration tests. Record cold/warm separately and compare the same commit, fixture and runner class; no absolute performance threshold before a baseline exists.

## P2 business audit (source inspection, not full acceptance)

- Subscription: YAML import and explicit HTTPS download exist. Node profiles are session-only; secure persistence and deletion/restart tests remain open.
- Routing: smart/global/strict, custom validation, policy persistence and native route observations exist. PR #2 merged; reverify REJECT/completed records in the combined baseline.
- Browser: HTTPS, tabs, bookmarks/history exist. Native views enforce HTTPS. HTTP, private IPv4/IPv6 and localhost/loopback are deliberately not yet enabled.
- Phase 3: design an explicit local-address policy enforced consistently by Dart, Android, iOS, HarmonyOS and Mihomo; consider DNS rebinding, redirects, subresources, proxy credentials and private-address handling. Never broaden transport or change TLS verification before regression tests.
- Isolation: Android fixture test covers authenticated HTTPS and rejected domain; three physical-device isolation evidence sets and release verification remain open.

## P3 interface design

Use Material 3 and existing Flutter widgets. Browser-first shell with a visible readiness/route state, address bar, tab switcher and navigation; a distinct proxy dashboard for node/strategy/rules/logs. Keep fail-closed controls disabled before native readiness. Preserve focus, draft URL and accessibility semantics. Add narrow-screen, large-text, light/dark and disabled-state widget tests before replacing the current subscription-first shell. Do not change routing policy labels or introduce a direct mode silently.
