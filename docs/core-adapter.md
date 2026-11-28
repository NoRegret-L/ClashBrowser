# CoreAdapter / subscription milestone

Native SDK artifacts passed all four jobs in run 45953035721. The native libraries have not yet been packaged with the app. This milestone implements the Dart-side contract and node-only import, not native handlers.

- Uses Dart yaml 3.1.3, not a handwritten YAML parser. Node fields are allowlisted; unsupported nodes fail the whole import. Six basic protocol types are recognized (HTTP, SOCKS5, SS, Trojan, VMess, VLESS); only a limited subset of transports/options is supported. The upstream core must validate protocol-specific semantics before applying config.
- All original non-node settings are ignored, including original rule groups, listeners, controllers and TUN. UI explains this before import. In-memory multiple profile management only; no remote URL fetching, storage, auto-refresh or actual node activation yet.
- A generated configuration contains a single selected node, explicit domain suffix rules and default REJECT. No implicit DIRECT; overlaps between proxy and direct suffixes are rejected. This is a conservative first milestone, not complete Clash compatibility.
- Native adapter must allocate an authenticated or otherwise isolated loopback listener, insert its port, validate projected config again, start and verify readiness. Channel acknowledgment alone cannot prove network isolation. Browser WebView proxy installation is a separate mandatory gate; no WebView exists in this version. Native start/stop should be serialized and return only on completion.
- No subscription data or secrets are logged or written to disk by this implementation. Dart memory cannot guarantee secure erasure. The UI does not call the native channel.
- Unit tests cover projection, unsafe input, default REJECT and mocked lifecycle; widget test covers import/delete/offline display. These are not device-level networking tests. No new arbitrary routing weights or heuristic tuning parameters.

Next: implement each native channel handler and package the matching SDK; then wire WebView proxy, test isolation and add secure storage/explicit subscription URL fetching.
