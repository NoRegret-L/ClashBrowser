import 'dart:io';
import 'package:flutter/services.dart';
import 'native_loopback.dart';

import 'subscription.dart';
import 'builtin_rules.dart';

enum CoreState { offline, starting, listenerReady, stopping, failed }

class CoreEndpoint {
  CoreEndpoint._(this.port, this.username, this.password);
  final String? username;
  final String? password;
  final int port;
  String get host => '127.0.0.1';
}

/// Shared contract. Listener readiness is NOT WebView proxy readiness.
abstract interface class CoreAdapter {
  CoreState get state;
  Future<CoreEndpoint> start(SubscriptionProfile profile, {
    required String selectedNode,
    RoutingMode routingMode = RoutingMode.strict,
    bool adBlock = true,
    Iterable<String> proxyDomains = const [],
    Iterable<String> directDomains = const [],
  });
  Future<void> stop();
}

/// Real native backend on supported mobile platforms; injectable test channel.
/// No generic action invocation, VPN, TUN or system-proxy methods are exposed.
class ChannelCoreAdapter implements CoreAdapter {
  ChannelCoreAdapter({MethodChannel? channel})
      : _channel = channel;

  Directory? _home;
  bool get _native => _channel == null && NativeLoopback.supported;
  MethodChannel get _testChannel => _channel ?? const MethodChannel('clashbrowser/core/v1');

  Future<Map<String, dynamic>?> _start(String config, RoutingMode routingMode) async {
    if (!_native) return _testChannel.invokeMapMethod<String, dynamic>('startLoopback', {'configJson': config});
    _home = await Directory.systemTemp.createTemp('clashbrowser-core-');
    if (routingMode == RoutingMode.smart) await BuiltinRules.stage(_home!);
    return NativeLoopback.command({'action': 'start', 'configJson': config, 'homeDir': _home!.path});
  }

  Future<void> _stop() async {
    if (!_native) { await _testChannel.invokeMethod<void>('stopLoopback'); return; }
    final reply = await NativeLoopback.command({'action': 'stop'});
    if (reply['stopped'] != true) throw StateError('Native stop failed');
    final home = _home;
    _home = null;
    if (home != null && await home.exists()) await home.delete(recursive: true);
  }

  final MethodChannel? _channel;
  CoreState _state = CoreState.offline;

  @override
  CoreState get state => _state;

  @override
  Future<CoreEndpoint> start(SubscriptionProfile profile, {
    required String selectedNode,
    RoutingMode routingMode = RoutingMode.strict,
    bool adBlock = true,
    Iterable<String> proxyDomains = const [],
    Iterable<String> directDomains = const [],
  }) async {
    if (_state != CoreState.offline) {
      throw StateError('Stop the core before starting again');
    }
    final config = profile.buildConfig(
      selectedNode: selectedNode,
      routingMode: routingMode,
      adBlock: adBlock,
      proxyDomains: proxyDomains,
      directDomains: directDomains,
    );
    _state = CoreState.starting;
    try {
      final response = await _start(config, routingMode);
      final port = response?['port'];
      if (response?['host'] != '127.0.0.1' ||
          response?['ready'] != true ||
          response?['tunEnabled'] != false ||
          port is! int || port < 1 || port > 65535 ||
          (_native && (response?['username'] != 'browser' ||
            response?['password'] is! String || (response!['password'] as String).isEmpty))) {
        throw StateError('Native listener acknowledgement is invalid');
      }
      _state = CoreState.listenerReady;
      return CoreEndpoint._(port, response?['username'] as String?, response?['password'] as String?);
    } catch (_) {
      _state = CoreState.failed;
      // Prevent overlapping lifecycle operations during rollback.
      _state = CoreState.stopping;
      try {
        await _stop();
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
      await _stop();
      _state = CoreState.offline;
    } catch (_) {
      _state = CoreState.failed;
      throw StateError('Native proxy stop not acknowledged');
    }
  }
}
