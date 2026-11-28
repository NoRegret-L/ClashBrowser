# Phase 3 local access: safety-first implementation slice

This branch does not activate new browser transports. It adds a pure Dart candidate classifier and a host integration test for authenticated HTTP to IPv4 and IPv6 loopback origins using explicit test-only DIRECT rules. Existing HTTPS-only navigation remains unchanged until native enforcement is available.

The classifier uses RFC 1918 IPv4, RFC 4193 IPv6 ULA, IPv4 loopback and IPv6 ::1, with exact localhost. No DNS lookup is performed. Localhost still needs a separately enforced native resolution policy. Public HTTP candidate classification is not an authorization to load a URL. Reject numeric aliases, mapped IPv6, link-local/metadata, unspecified, multicast, credentials, invalid ports and the authenticated proxy's own loopback port. Public literal addresses and LAN DNS names are excluded from this first slice.

## Required activation gates

1. Separate website authentication from proxy authentication on Android and HarmonyOS. Current callbacks match host/realm but do not identify a proxy challenge reliably. Never send the random proxy secret to an origin. iOS already uses isProxy and exact endpoint checks; retain them.
2. Require explicit per-session or persisted user origin authorization; default is off. Separate public HTTP consent from local access. Prevent redirects/subresources, DNS rebinding and mixed-content downgrade from broadening the granted origin. Enforce address policy at the actual native dial boundary, not only the address bar. Preserve custom rule order and default rejection; never expose the listener on LAN, set a device-wide proxy, add TUN or enable direct fallback.
3. Verify the Android and HarmonyOS WebView local bypass behavior; Android already calls removeImplicitRules, but device evidence is mandatory. iOS must retain failoverAllowed=false. Block access to the proxy's own endpoint, including aliases. Do not relax TLS verification or JS/file/permission restrictions.
4. Extend device fixtures to test public HTTP, authorized IPv4/IPv6 LAN and loopback, origin 401 challenges, proxy 407, rejected local origins, redirects, subresources and credential non-disclosure on all supported platforms. Full physical-device isolation evidence remains required.

No UI switch or production allowlist is installed by this slice. The new host test checks the native authenticated path, not device WebView safety or LAN reachability. Failed or unavailable IPv6 test infrastructure is not treated as success.
