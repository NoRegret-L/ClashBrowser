import 'package:clashbrowser/core/browser_address.dart';
import 'package:clashbrowser/core/local_access_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proxyPort = 32123;
  LocalAccessCandidate? candidate(String value) =>
      classifyAccessCandidate(value, proxyPort: proxyPort);

  test('phase 3 classifies HTTP, private IPv4/IPv6 and exact loopback', () {
    for (final value in ['http://example.com/path', 'https://example.com']) {
      expect(candidate(value)?.scope, CandidateScope.publicDomain, reason: value);
    }
    expect(candidate('http://example.com')?.cleartext, isTrue);
    expect(candidate('example.com')?.cleartext, isFalse);
    for (final value in ['http://10.0.0.1:8080', 'http://172.16.0.1',
      'http://172.31.255.254', 'http://192.168.1.1', 'http://[fd00::1]:8080',
      'https://[fc00::1]']) {
      expect(candidate(value)?.scope, CandidateScope.privateNetwork, reason: value);
    }
    for (final value in ['http://localhost:8080', 'http://127.0.0.1:8080',
      'http://127.0.0.2', 'http://[::1]:8080', 'http://[0:0:0:0:0:0:0:1]']) {
      expect(candidate(value)?.scope, CandidateScope.loopback, reason: value);
    }
  });

  test('reject ambiguous, non-local literal and unsafe authorities', () {
    for (final value in [
      'http://localhost:32123', 'http://127.0.0.2:32123', 'http://[::1]:32123',
      'http://127.1', 'http://2130706433', 'http://0x7f.0.0.1',
      'http://127.0.0.0x1', 'http://0177.0.0.1', 'http://127.000.0.1',
      'http://[::ffff:127.0.0.1]', 'http://[::127.0.0.1]',
      'http://[fe80::1%25eth0]', 'http://[fe80::1]', 'http://169.254.169.254',
      'http://0.0.0.0', 'http://[::]', 'http://224.0.0.1', 'http://[ff02::1]',
      'http://172.15.0.1', 'http://172.32.0.1', 'http://8.8.8.8',
      'http://foo.localhost', 'http://router.local', 'http://router.home.arpa',
      'http://localhost.', 'http://%6cocalhost', 'http://user:secret@localhost',
      'http://localhost@public.example', 'http://localhost:0', 'http://localhost:65536',
      'http://localhost:abc', 'http://localhost\\evil.example', 'file:///etc/passwd',
    ]) {
      expect(candidate(value), isNull, reason: value);
    }
  });

  test('classification does not weaken the existing navigation policy', () {
    for (final value in ['http://example.com', 'http://localhost:8080',
      'https://127.0.0.1', 'https://[::1]', 'https://192.168.1.1']) {
      expect(browserAddress(value), isNull, reason: value);
    }
  });
}
