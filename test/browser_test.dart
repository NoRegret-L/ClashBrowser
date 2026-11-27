import 'package:clashbrowser/core/browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clashbrowser/core/core_adapter.dart';
import 'package:clashbrowser/core/subscription.dart';

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
  testWidgets('shared browser toolbar is disabled before native readiness', (tester) async {
    const channel = MethodChannel('test/browser-core');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async =>
      call.method == 'startLoopback' ? {
        'host': '127.0.0.1', 'port': 12345, 'ready': true,
        'tunEnabled': false, 'username': 'browser', 'password': 'fake',
      } : null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final profile = SubscriptionProfile.parse(
      'proxies: [{name: test, type: http, server: proxy.example, port: 80}]');
    final endpoint = await ChannelCoreAdapter(channel: channel).start(
      profile, selectedNode: 'test');
    await tester.pumpWidget(MaterialApp(home: BrowserScreen(endpoint: endpoint)));
    expect(find.byKey(const Key('browser-address')), findsOneWidget);
    for (final label in ['打开', '后退', '前进', '刷新', '停止加载']) {
      expect(tester.widget<IconButton>(find.byTooltip(label)).onPressed, isNull);
    }
  });
}
