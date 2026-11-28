# Embedded native SDK milestone

Builds installable-format Android and unsigned Apple/HarmonyOS app artifacts after the four native SDK jobs complete. The Android and HarmonyOS apps package verified shared libraries; the iOS application links a local Flutter plugin to the verified XCFramework. The user can request a read-only native symbol probe. No runtime network listener is opened by the probe, and CoreAdapter's start/stop channel remains unavailable.

Why not enable the previous SDKs directly? ArkClash's pinned lifecycle intentionally removes business listeners at start and restores them when a TUN is attached. Android's pinned applyConfig may fall back to a default config on failure to preserve a VPN. These are unsuitable fail-closed semantics without an audited, dedicated no-TUN adapter. iOS service runtime policy and listener behavior also need validation. Do not call VPN APIs or fake an endpoint to get a green test.

The build verifies SDK checksums, APK/HAP library contents, and successful Apple native symbol linkage. These are packaging and compile gates only: on-device native initialization, actual CoreAdapter start/stop and authenticated/isolated loopback listener remain unverified and disabled. No device runtime probes are executed by CI yet. Existing offline app CI is preserved; the native artifacts are built separately.

Source snapshots and licenses accompany experimental artifacts. Full corresponding source and app licensing review are required before distributing releases. No signing keys or subscription secrets used.
