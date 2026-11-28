# ArkWeb experimental JavaScript mode

Gate: CI 45979221116 and Android device-auth 45979221096 attempt 2 passed at 0e3ab6d. The latter verified authenticated CONNECT, TLS redirect, submission of the unmatched URL and UI failure, and no unmatched request at the controlled relay. This is not HarmonyOS device evidence.

Official API references:
- https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-webviewcontroller/
- https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-securityparams/

ArkWeb advanced security is process-global and must be configured before initializeWebEngine and before any Web component. BrowserPlugin configures once at engine registration, before its view factory constructs a controller. The native API is void; lack of an exception is not proof of egress enforcement. Restrict the experimental allowlist to the documented M144 evergreen engine, not legacy M114/M132 or unknown versions. Use disableNonProxyUDP and disableServiceWorker, plus disable automatic preconnect, because the causal risk is bypassing the authenticated TCP proxy or background activity outside a live tab. No blanket disabling of JIT/WASM/WebGL solely for network isolation, no JS injection, no new library, no numeric tuning constants. Retain HTTPS-only navigation, TLS validation, deny permissions, file/DOM storage off, and the existing proxy. If configuration fails or the engine does not match, JavaScript remains off.

Build opt-in (inside existing OHOS SDK build environment with verified embedded SDK):

    CLASHBROWSER_EMBED_OHOS=1 CLASHBROWSER_OHOS_EXPERIMENTAL_JS=true bash ci/build-ohos.sh

The flag defaults false and affects only OHOS. Android/iOS continue their existing static mode. The native view additionally requires valid endpoint credentials and the guarded ArkWeb setup; a Dart flag alone cannot enable JS. The Flutter UI identifies the experimental mode without claiming isolation is verified. The global settings are attempted even for static builds, to keep one early initialization path. This can change speculative preconnect behavior process-wide; only the WebView engine is affected, not other apps. Service Worker-dependent sites and some WebRTC calls may fail. The explicit M144 allowlist intentionally requires review for newer evergreen versions.

Before shipping JS enabled by default, verify on a supported HarmonyOS device: correct and incorrect proxy credentials, real TLS page with a script-generated DOM change and proxied fetch, unmatched domains, redirect and iframe, Service Worker registration denied, WebRTC STUN/UDP and DNS egress observed from a controlled gateway, stopping the core during navigation, tab closure and new view, and independent app routing. Compare the flag=false and true builds, and verify old/legacy kernels remain static. No device-side assertions have been executed by this commit.

CI builds both HAP variants in the same embedded OHOS job when the flag is unset; explicit true/false still build only one. Static remains the original artifact name; experimental is clashbrowser-experimental-js.hap in the same artifact. Both are unsigned, must be signed before installing. The ArkTS enum is M144 (the NDK C enum has the ARKWEB_ prefix). Verify isAutoPreconnectEnabled() after initialization as an additional gate. See [device isolation regression](ohos-isolation-test.md) for the owned HTTPS/STUN probe and positive controls.
