import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashbrowser/core/browser.dart';
import 'package:clashbrowser/core/core_adapter.dart';
import 'package:clashbrowser/core/subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A controlled local upstream: only records CONNECT destinations and rejects
/// tunnels. No public network, TLS bypass, real subscription or secret needed.
class LocalUpstream {
  LocalUpstream(this.server) {
    server.listen(_accept);
  }
  final ServerSocket server;
  final List<String> destinations = [];
  final Set<Socket> _sockets = {};
  final Completer<void> accepted = Completer<void>();
  static const target = 'browser-auth-probe.invalid:443';

  static Future<LocalUpstream> start() async =>
      LocalUpstream(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> _accept(Socket socket) async {
    _sockets.add(socket);
    try {
      String? first;
      await for (final line in socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 10))) {
        first ??= line;
        if (line.isNotEmpty) continue;
        final parts = first.split(' ');
        if (parts.length >= 2 && parts[0] == 'CONNECT') {
          destinations.add(parts[1]);
          if (parts[1] == target && !accepted.isCompleted) accepted.complete();
        }
        socket.write('HTTP/1.1 502 Bad Gateway\r\n'
            'Content-Length: 0\r\nConnection: close\r\n\r\n');
        await socket.flush();
        break;
      }
    } catch (_) {
      // Fixture connections may be cancelled during test teardown.
    } finally {
      socket.destroy();
      _sockets.remove(socket);
    }
  }

  Future<void> close() async {
    await server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
  }
}

Future<void> waitFor(WidgetTester tester, bool Function() condition,
    String failure) async {
  // Deadline is a test watchdog, not a browser routing parameter.
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail(failure);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real WebView authenticates to embedded Mihomo and follows REJECT',
      (tester) async {
    final fixture = (await tester.runAsync(LocalUpstream.start))!;
    final core = ChannelCoreAdapter();
    try {
      final profile = SubscriptionProfile.parse(
          'proxies: [{name: fixture, type: http, server: 127.0.0.1, port: ${fixture.server.port}}]');
      final endpoint = (await tester.runAsync(() => core.start(profile,
          selectedNode: 'fixture',
          proxyDomains: ['browser-auth-probe.invalid'])))!;
      await tester.pumpWidget(MaterialApp(home: BrowserScreen(endpoint: endpoint)));
      final open = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == '打开');
      await waitFor(tester,
          () => tester.widget<IconButton>(open).onPressed != null,
          'Native WebView proxy never became ready');

      final address = find.byKey(const Key('browser-address'));
      await tester.enterText(address, 'https://browser-auth-probe.invalid/');
      await tester.tap(open);
      await waitFor(tester, () => fixture.accepted.isCompleted,
          'Authenticated CONNECT never reached the local upstream');
      expect(fixture.destinations, contains(LocalUpstream.target));

      await waitFor(tester,
          () => find.text('网页加载失败（无直连回退）').evaluate().isNotEmpty,
          'Controlled upstream rejection did not finish the first navigation');

      // The core defaults to REJECT. A second domain must not reach upstream.
      await tester.enterText(address, 'https://browser-blocked-probe.invalid/');
      await tester.tap(open);
      await waitFor(tester,
          () => find.text('网页加载失败（无直连回退）').evaluate().isNotEmpty,
          'Rejected navigation did not report a failure');
      expect(fixture.destinations, isNot(contains('browser-blocked-probe.invalid:443')));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        try { await core.stop(); } finally { await fixture.close(); }
      });
    }
  });
}
