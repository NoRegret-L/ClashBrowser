# Mihomo native SDK build gate

This stage builds separate experimental native libraries, NOT a linked browser app. The Flutter app stays offline. Version-aligned upstream implementations are pinned in upstreams.json.

- Android: standalone JNI library (AAR). Uses upstream Go build, JNI export check and Gradle. Its VPN-related API must not be called by the browser adapter.
- iOS: ProjectClash's gomobile bindings, iOS device and simulator slices only. No NetworkExtension target is created by ClashBrowser.
- HarmonyOS: ArkClash Go c-shared core, its musl/TLS patches and OpenHarmony NDK. No VpnExtensionAbility is copied.
- Linux host smoke test: use the same iOS derivative source to test actual HTTP inbound, explicit DIRECT, selected upstream proxy over CONNECT, default REJECT, and listener shutdown. This is not a native-device or WebView test.

Decision: do not write new protocol engines; reuse upstream native bindings. Platform differences remain behind a future lifecycle/configuration adapter. This reduces integration risk but leaves different wrapper APIs, core forks, runtime memory, and loopback access isolation to verify. No arbitrary performance tuning or policy thresholds added; timeouts only bound CI test execution.

## Before enabling browser network

Use a strict configuration projection rather than blindly applying full subscription YAML. Reject unexpected listeners, external controllers, scripts, TUN and OS routing mutations; protect loopback access; preserve explicit DIRECT and REJECT semantics; verify readiness before navigation. An unavailable proxy must not trigger browser-level direct fallback. The host fixture is synthetic and no user subscription is accepted in this stage. Native SDK build success does not imply successful native initialization.

## License and distribution

All three chosen wrappers declare GPL-3.0. Artifacts are experimental CI packages with pinned source snapshots, license and checksums. Do not publish a release or distribute a combined application until complete corresponding source, dependency notices and compatible project licensing have been reviewed. No signing credentials or subscription secrets are used.
