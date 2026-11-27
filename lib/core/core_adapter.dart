import 'package:flutter/services.dart';

import 'subscription.dart';

enum CoreState { offline, starting, listenerReady, stopping, failed }

class CoreEndpoint {
  CoreEndpoint._(this.port);
  final int port;
  String get host => '127.0.0.1';
}

/// Shared contract. Listener readiness is NOT WebView proxy readiness.
abstract interface class CoreAdapter {
  CoreState get state;
  Future<CoreEndpoint> start(SubscriptionProfile profile, {
    required String selectedNode,
    Iterable<String> proxyDomains = const [],
    Iterable<String> directDomains = const [],
  });
  Future<void> stop();
}

/// Native handlers are intentionally not registered in the bootstrap app.
/// No generic action invocation, VPN, TUN or system-proxy methods are exposed.
class ChannelCoreAdapter implements CoreAdapter {
  ChannelCoreAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('clashbrowser/core/v1');

  final MethodChannel _channel;
  CoreState _state = CoreState.offline;

  @override
  CoreState get state => _state;

  @override
  Future<CoreEndpoint> start(SubscriptionProfile profile, {
    required String selectedNode,
    Iterable<String> proxyDomains = const [],
    Iterable<String> directDomains = const [],
  }) async {
    if (_state != CoreState.offline) {
      throw StateError('Stop the core before starting again');
    }
    final config = profile.buildConfig(
      selectedNode: selectedNode,
      proxyDomains: proxyDomains,
      directDomains: directDomains,
    );
    _state = CoreState.starting;
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'startLoopback', {'configJson': config},
      );
      final port = response?['port'];
      if (response?['host'] != '127.0.0.1' ||
          response?['ready'] != true ||
          response?['tunEnabled'] != false ||
          port is! int || port < 1 || port > 65535) {
        throw StateError('Native listener acknowledgement is invalid');
      }
      _state = CoreState.listenerReady;
      return CoreEndpoint._(port);
    } catch (_) {
      _state = CoreState.failed;
      // Prevent overlapping lifecycle operations during rollback.
      _state = CoreState.stopping;
      try {
        await _channel.invokeMethod<void>('stopLoopback');
      } catch (_) {
        // Remain failed: absence of an acknowledgement is not proof of stop.
      } finally {
        _state = CoreState.failed;
      }
      throw StateError('Native proxy unavailable');
    }
  }

  @override
  Future<void> stop() async {
    if (_state == CoreState.offline) return;
    if (_state == CoreState.starting || _state == CoreState.stopping) {
      throw StateError('Core operation already in progress');
    }
    _state = CoreState.stopping;
    try {
      await _channel.invokeMethod<void>('stopLoopback');
      _state = CoreState.offline;
    } catch (_) {
      _state = CoreState.failed;
      throw StateError('Native proxy stop not acknowledged');
    }
  }
}
