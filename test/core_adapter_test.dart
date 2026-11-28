import 'package:clashbrowser/core/core_adapter.dart';
import 'package:clashbrowser/core/subscription.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/core');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final profile = SubscriptionProfile.parse(
    'proxies: [{name: test, type: http, server: proxy.example, port: 80}]');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('requires explicit local readiness, then stops', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'startLoopback') {
        return {'host': '127.0.0.1', 'port': 12345, 'ready': true,
          'tunEnabled': false};
      }
      return null;
    });
    final adapter = ChannelCoreAdapter(channel: channel);
    final endpoint = await adapter.start(profile, selectedNode: 'test');
    expect(endpoint.host, '127.0.0.1');
    expect(endpoint.port, 12345);
    expect(adapter.state, CoreState.listenerReady);
    await adapter.stop();
    expect(adapter.state, CoreState.offline);
    expect(calls, ['startLoopback', 'stopLoopback']);
  });

  test('unsafe response rolls back and never reports readiness', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'startLoopback') {
        return {'host': '0.0.0.0', 'port': 12345, 'ready': true,
          'tunEnabled': false};
      }
      return null;
    });
    final adapter = ChannelCoreAdapter(channel: channel);
    await expectLater(adapter.start(profile, selectedNode: 'test'), throwsStateError);
    expect(adapter.state, CoreState.failed);
    expect(calls, ['startLoopback', 'stopLoopback']);
  });

  test('missing platform handler remains failed', () async {
    final adapter = ChannelCoreAdapter(channel: channel);
    await expectLater(adapter.start(profile, selectedNode: 'test'), throwsStateError);
    expect(adapter.state, CoreState.failed);
  });
}
