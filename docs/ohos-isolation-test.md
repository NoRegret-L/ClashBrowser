# HarmonyOS JavaScript device isolation regression

This is a controlled device test harness, not an executed device result. Requires a physical HarmonyOS 7.0/M144 device, two signed variants, an owned TLS origin (valid cert for both hostnames), an owned proxy node, controlled DNS and an owned STUN endpoint. Do not use real browsing sessions or public STUN services. Use separate non-overlapping DNS suffixes so the allow rule cannot include the blocked or STUN host. Set only the allowed host in BROWSER-PROXY, no DIRECT rules. Use unique hostnames per run to defeat DNS cache; capture a dedicated device/network and record UTC start/end. Disable cellular during the Wi-Fi capture or capture all active network paths.

1. Start the controlled origin. Both TLS DNS names must resolve to the host running the fixture. Use a publicly trusted test certificate; never bypass SSL errors. Example names below are placeholders:
   
       python3 ci/ohos-isolation-probe.py --bind 0.0.0.0 \
         --allowed "$ALLOWED_HOST" --blocked "$BLOCKED_HOST" \
         --stun "$STUN_HOST" --cert "$TEST_CERT" --key "$TEST_KEY" \
         --events "$RUN_DIR/events.jsonl"

   Run coturn as STUN-only on the owned STUN host (restrict firewall to the test network); validate reachability independently. See https://github.com/coturn/coturn/blob/master/man/man1/turnserver.1. No public TURN relay required.

2. Start capture on the controlled gateway *before launching the app* (Wi-Fi client traffic on both IPv4 and IPv6), and collect DNS resolver and proxy-node logs. For example on a dedicated test VLAN:

       sudo tcpdump -i "$TEST_INTERFACE" -nn -s 0 -w "$RUN_DIR/device.pcap"

   Capture on the STUN host too. Use a normal browser on the same test device/network to run the same page as positive control: confirm actual STUN datagrams and a reachable blocked origin; if not observed, absence of STUN/blocked traffic in ClashBrowser is INCONCLUSIVE. Keep separate capture files. Validate that the proxy-node egress IP is distinguishable from the device egress.

3. Install the default signed HAP and start ClashBrowser with the test subscription. Open the allowed HTTPS origin. It must show STATIC, no js event; confirm origin peer is the proxy. Repeat with the signed experimental HAP on M144. It must show the experimental JS indicator and page text "JavaScript executed"; press Run once. Record run UUID, wait until fetch/worker/ICE results are observable; ICE timeout or missing events are inconclusive (do not equate timeout to pass). Stop ICE. Verify in the origin log:
   - js and fetch-ok events, fetch-received and allowed origin source matches proxy egress;
   - blocked-error with no blocked-received for the run (negative HTTPS route);
   - sw-unavailable or sw-denied, no worker-received or sw-registered;
   - ice-start and ice-complete or ice-unavailable; no non-proxy STUN UDP packets in device and STUN-host captures. A candidate type alone is not evidence of a leak or its absence. Any direct packet to STUN is failure.
   - inspect actual device DNS queries (including encrypted resolver connections, IPv6, and DNS-prefetch), proxy logs, destination addresses, and unexpected direct TCP/UDP. Authoritative DNS logs alone cannot identify which device initiated resolution.

4. Repeat after stop/restart, fresh tab, and core stop during navigation. Test independent app traffic with the core running. Confirm no unapproved direct traffic and normal separate-app route. Repeat on a legacy/unsupported engine: JS stays off. Also test incorrect proxy credentials, expired/untrusted TLS, cross-origin redirects/iframes and downloads separately. A missing marker, missing pcap, disabled positive control or ambiguous source is inconclusive, not a pass.

Never enable JavaScript by default based only on a green build or this probe's UI. Store captures locally with limited access; avoid full real-user captures. File hashes and exact app commit, build flag, OS/ArkWeb version, proxy and gateway configuration belong in the test record.
