import 'package:clashbrowser/core/browser.dart';
import 'package:clashbrowser/core/core_adapter.dart';
import 'package:clashbrowser/core/subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> waitFor(WidgetTester tester, bool Function() condition,
    String failure) async {
  // Test watchdog; not a browser routing parameter.
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  final status = find.byKey(const Key('browser-status'));
  final address = find.byKey(const Key('browser-address'));
  fail('$failure; status: ${status.evaluate().isEmpty ? "missing" : tester.widget<Text>(status).data}; address: ${address.evaluate().isEmpty ? "missing" : tester.widget<TextField>(address).controller!.text}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Integration tests default to a real IME. Flutter issue #134604 describes
  // repeated enterText retaining the old value. Isolate synthetic input from IME.
  setUp(() => binding.testTextInput.register());
  tearDown(() => binding.testTextInput.unregister());

  testWidgets('real WebView authenticates, loads TLS page and rejects unmatched domain',
      (tester) async {
    const port = int.fromEnvironment('TEST_PROXY_PORT');
    expect(port, inInclusiveRange(1, 65535), reason: 'Run ci/android-device-test.sh');
    final core = ChannelCoreAdapter();
    try {
      final profile = SubscriptionProfile.parse(
          'proxies: [{name: fixture, type: http, server: 127.0.0.1, port: $port}]');
      final endpoint = (await tester.runAsync(() => core.start(profile,
          selectedNode: 'fixture',
          proxyDomains: ['browser-tls-probe.invalid'])))!;
      await tester.pumpWidget(MaterialApp(home: BrowserScreen(endpoint: endpoint)));
      final open = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == '打开');
      await waitFor(tester,
          () => tester.widget<IconButton>(open).onPressed != null,
          'Native WebView proxy never became ready');

      final address = find.byKey(const Key('browser-address'));
      await tester.enterText(address, 'https://browser-tls-probe.invalid/start');
      await tester.tap(open);
      await waitFor(tester,
          () => tester.widget<TextField>(address).controller!.text ==
              'https://browser-tls-probe.invalid/verified',
          'Authenticated TLS navigation and redirect did not complete');
      expect(find.text('网页加载完成 · 应用内代理'), findsOneWidget);
      print('TEST: authenticated TLS redirect reached /verified');
      expect(find.text('网页加载失败（无直连回退）'), findsNothing);
      expect(find.text('代理认证失败或不兼容'), findsNothing);

      const blocked = 'https://browser-blocked-probe.invalid/';
      await tester.showKeyboard(address);
      await tester.pump();
      expect(tester.widget<TextField>(address).focusNode!.hasFocus, isTrue,
          reason: 'Address field must own keyboard focus');
      await tester.enterText(address, blocked);
      await tester.pump();
      expect(tester.widget<TextField>(address).controller!.text, blocked,
          reason: 'Second synthetic text entry must update the address field');
      // Exercise the keyboard submission path rather than tapping a potentially
      // moving native-platform-view overlay while the keyboard is showing.
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      print('TEST: submitted unmatched domain');
      expect(tester.widget<TextField>(address).controller!.text, blocked,
          reason: 'The unmatched address must actually be submitted');
      await waitFor(tester,
          () => find.text('网页加载失败（无直连回退）').evaluate().isNotEmpty,
          'Rejected navigation did not report a failure');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => core.stop());
    }
  });
}
