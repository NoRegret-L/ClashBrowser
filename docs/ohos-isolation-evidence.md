# Offline scoped isolation evidence check

Use Wireshark/TShark's official command-line decoder, not a new packet parsing library. Install tshark on the isolated analysis machine. The checker runs offline with name resolution disabled, uses only the controlled device IPs and targets, and emits counts and hashes rather than arbitrary browsing data.

Before running, record the app commit, signed artifact SHA-256, OS/ArkWeb version, device IP addresses (including IPv6 privacy addresses), actual DNS answers for each controlled name, proxy node addresses and expected origin-observed proxy egress. Collect separate positive-control and experimental pre-NAT gateway captures, beginning before app launch and ending after the probe. Use an isolated test device and network, no cellular/alternate path, and distinct IPs for proxy and test endpoints. Origin and blocked host may share an IP (then counts overlap). The positive control must really contact all controlled endpoints directly, including STUN UDP. The experimental allowed request must actually reach the origin from the expected proxy egress. Copy the origin event log from the controlled server. Use unique names per run; if DNS caching or incomplete coverage is possible, mark capture_complete false.

Example manifest (documentation-only reserved names and IPs, replace with the actual owned environment):

    {
      "run": "12345678-1234-1234-1234-123456789012",
      "allowed_host": "allowed.example",
      "blocked_host": "blocked.example",
      "stun_host": "stun.example",
      "device_ips": ["192.0.2.10", "2001:db8::10"],
      "proxy_ips": ["192.0.2.20"],
      "proxy_egress_ips": ["192.0.2.21"],
      "origin_ips": ["192.0.2.30"],
      "blocked_ips": ["192.0.2.31"],
      "stun_ips": ["192.0.2.32"],
      "control_pcap": "control.pcap",
      "trial_pcap": "trial.pcap",
      "events": "events.jsonl",
      "capture_complete": false
    }

    python3 ci/verify-ohos-isolation.py manifest.json

Exit 0 = PASS_SCOPED (only declared endpoints, observed plaintext DNS names, fetch, SW and actual ICE completion); exit 1 = FAIL; exit 2 = INCONCLUSIVE. Missing positive control, missing packets, missing ICE completion, invalid input or decoder error must never produce success. If ICE is unavailable, this particular verifier is inconclusive even if that is the intended platform configuration. This conservative choice tests the actual UDP constraint instead of claiming enforcement from an absent feature. No time threshold or probabilistic scoring. Do not interpret PASS_SCOPED as full device network isolation. Encrypted DNS, other destinations, non-test traffic, proxy-stop, redirects, and independent app traffic still require the companion device procedure. Keep pcap files, addresses and run manifest local; the checker does not upload them.

Run the parser/decision unit tests without a device:

    python3 ci/test-ohos-isolation-verifier.py

TShark manual: https://www.wireshark.org/docs/man-pages/tshark.html
