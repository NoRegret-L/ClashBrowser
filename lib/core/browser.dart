import 'package:flutter/services.dart';
import 'core_adapter.dart';

/// Native screen owns its WebView and proxy configuration.
/// This method completes only after the native screen is closed.
class BrowserBridge {
  static const _channel = MethodChannel('clashbrowser/browser/v1');

  static Future<void> open(CoreEndpoint endpoint) async {
    if (endpoint.username != 'browser' ||
        endpoint.password == null || endpoint.password!.isEmpty) {
      throw StateError('Proxy authentication unavailable');
    }
    final closed = await _channel.invokeMethod<bool>('open', {
      'port': endpoint.port,
      'username': endpoint.username,
      'password': endpoint.password,
    });
    if (closed != true) throw StateError('Browser not available');
  }
}
