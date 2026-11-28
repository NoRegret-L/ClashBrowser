import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("verifier", Path(__file__).with_name("verify-ohos-isolation.py"))
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

class EvidenceTest(unittest.TestCase):
    def test_positive_control_required(self):
        c = dict(device=10, proxy=0, stun=1, blocked=0, origin=1)
        t = dict(device=10, proxy=1, stun=0, blocked=0, origin=0)
        failures, missing = v.inspect_counts(c, t)
        self.assertFalse(failures)
        self.assertTrue(missing)
    def test_direct_traffic_fails(self):
        c = dict(device=10, proxy=0, stun=1, blocked=1, origin=1)
        t = dict(device=10, proxy=1, stun=1, blocked=0, origin=0)
        self.assertTrue(v.inspect_counts(c, t)[0])
        t["stun"] = 0
        self.assertEqual(v.inspect_counts(c, t), ([], []))
    def test_ipv6_and_ipv4_filter(self):
        self.assertEqual(v.address_filter(["192.0.2.2", "2001:db8::1"], "src"),
                         "(ip.src == 192.0.2.2 || ipv6.src == 2001:db8::1)")
        with self.assertRaises(ValueError):
            v.address_filter(["192.0.2.1 || udp"], "src")
    def test_events_require_actual_ice_and_matching_peer(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "events.jsonl"
            run = "12345678-1234-1234-1234-123456789012"
            good = ["js", "fetch-ok", "fetch-received", "blocked-error", "sw-denied",
                    "ice-start", "ice-complete"]
            def write(kinds, peer="192.0.2.1"):
                p.write_text("\n".join(json.dumps(dict(kind=k, run=run,
                    host="allowed.example", peer=peer)) for k in kinds))
            write(good)
            self.assertEqual(v.inspect_events(p, run, "allowed.example", "blocked.example", {"192.0.2.1"}), ([], []))
            write(good[:-1])
            self.assertTrue(v.inspect_events(p, run, "allowed.example", "blocked.example", {"192.0.2.1"})[1])
            write(good, "192.0.2.2")
            self.assertTrue(v.inspect_events(p, run, "allowed.example", "blocked.example", {"192.0.2.1"})[0])
            write(good + ["sw-registered"])
            self.assertTrue(v.inspect_events(p, run, "allowed.example", "blocked.example", {"192.0.2.1"})[0])

if __name__ == "__main__":
    unittest.main()
