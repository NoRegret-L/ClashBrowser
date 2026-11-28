import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'subscription.dart';

class SubscriptionLink {
  static Uri validate(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const FormatException('Expected an HTTPS subscription URL');
    }
    return uri;
  }

  /// Explicit, user-triggered bootstrap request, not browser page traffic.
  /// No automatic redirect, insecure TLS override, or credential logging.
  static Future<SubscriptionProfile> fetch(String input) async {
    final uri = validate(input);
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'ClashBrowser/0.0.1 Clash');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const FormatException('Subscription download failed');
        }
        // Resource guard, not a routing parameter: bound decompressed data.
        const maxBytes = 8 * 1024 * 1024;
        if (response.contentLength > maxBytes) {
          throw const FormatException('Subscription too large');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('Subscription too large');
          }
          bytes.add(chunk);
        }
        return SubscriptionProfile.parse(utf8.decode(bytes.takeBytes()));
      })().timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const FormatException('Subscription download or parse failed');
    } finally {
      client.close(force: true);
    }
  }
}
