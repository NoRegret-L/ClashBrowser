import 'package:clashbrowser/core/subscription_link.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('accepts explicit HTTPS subscription URLs with tokens', () {
    expect(SubscriptionLink.validate('https://example.com/sub?token=fake').host, 'example.com');
  });
  test('rejects plaintext, local file schemes, credentials and fragments', () {
    for (final url in ['http://example.com/sub', 'file:///tmp/sub', 'https://u:p@example.com/', 'https://example.com/#token']) {
      expect(() => SubscriptionLink.validate(url), throwsFormatException);
    }
  });
}
