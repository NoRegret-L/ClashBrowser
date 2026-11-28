# Architecture and acceptance gates

Only Android, iOS and HarmonyOS NEXT. No desktop targets.

Shared Flutter UI and configuration model; native adapters for Android WebView ProxyController, iOS WKWebsiteDataStore proxyConfigurations (iOS 17+), and ArkWeb ProxyController (API 15+). Candidates: [webview_all](https://github.com/abandoft/webview_all), [Mihomo](https://github.com/MetaCubeX/mihomo), [ArkClash](https://github.com/VOD-Studio/ArkClash), Flutter OHOS. Review licenses before incorporating code.

## Invariants

- No system VPN, TUN, network extension or system proxy changes.
- Loopback-only local proxy; assess other apps' ability to access the listener.
- Do not load remote pages until native proxy application and core readiness succeed. Explicit DIRECT rules only; no implicit direct fallback.
- Never log or commit subscription credentials. Validate imported YAML; disable TUN and external listeners.
- Domain rules belong to Mihomo; per-tab independent routing is deferred.

## Build baseline

Native Android and iOS shells are generated in CI; native platform projects will be committed once adapters are added. HarmonyOS uses the separately versioned Flutter OHOS fork with API 26 SDK. The community builder is an experimental dependency; no signing credentials or subscription data are supplied. Review and verify SDK provenance and licensing before production use.

1. Compile shell on all three platforms.
2. Integrate core and verify loopback HTTP CONNECT.
3. Verify proxy assignment, DNS, WebRTC, downloads, redirects, direct rules and failure behavior on devices.
4. Verify signing and installation.

The initial widget test asserts the visible offline state only; it does not test network isolation. No browser, proxy core or subscriptions exist yet. iOS and HarmonyOS artifacts are unsigned or unverified debug packages, not release-ready.
