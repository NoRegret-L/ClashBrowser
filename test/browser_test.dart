import 'package:clashbrowser/core/browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTPS address normalization', () {
    expect(browserAddress('example.com')?.toString(), 'https://example.com');
    expect(browserAddress('https://example.com/a?q=b')?.host, 'example.com');
  });
  test('rejects cleartext, credentials, local and unsupported schemes', () {
    for (final value in ['http://example.com', 'file:///etc/passwd',
      'https://user:pass@example.com', 'https://127.0.0.1',
      'https://[::1]', 'https://foo.localhost', 'https://localhost',
      'javascript:alert(1)', '']) {
      expect(browserAddress(value), isNull, reason: value);
    }
  });
}
