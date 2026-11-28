import 'dart:io';

/// Phase 3 candidate classification only. It never authorizes navigation.
enum CandidateScope { publicDomain, privateNetwork, loopback }

class LocalAccessCandidate {
  const LocalAccessCandidate(this.uri, this.scope);
  final Uri uri;
  final CandidateScope scope;
  bool get cleartext => uri.scheme == 'http';
}

/// Accept canonical IP literals and ordinary DNS names without DNS lookups.
/// A candidate must still pass native authentication, routing and origin policy.
LocalAccessCandidate? classifyAccessCandidate(String input, {required int proxyPort}) {
  if (proxyPort < 1 || proxyPort > 65535) return null;
  var text = input.trim();
  if (text.isEmpty || RegExp(r'[\s\\\x00-\x1f\x7f]').hasMatch(text)) return null;
  if (!text.contains('://')) text = 'https://$text';
  final match = RegExp(r'^(https?)://(\[[0-9a-fA-F:.]+\]|[a-zA-Z0-9.-]+)(?::([0-9]+))?(?:[/?#]|$)', caseSensitive: false).firstMatch(text);
  if (match == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.userInfo.isNotEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  final portText = match.group(3);
  final port = portText == null ? (uri.scheme == 'http' ? 80 : 443) : int.tryParse(portText);
  if (port == null || port < 1 || port > 65535) return null;
  final authorityHost = match.group(2)!.toLowerCase();
  final bracketed = authorityHost.startsWith('[');
  final host = bracketed ? authorityHost.substring(1, authorityHost.length - 1) : authorityHost;

  CandidateScope? scope;
  if (host == 'localhost') {
    scope = CandidateScope.loopback;
  } else {
    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      final b = ip.rawAddress;
      if (ip.type == InternetAddressType.IPv4) {
        if (bracketed || b.join('.') != host) return null;
        if (b[0] == 127) {
          scope = CandidateScope.loopback;
        } else if (b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168)) {
          scope = CandidateScope.privateNetwork;
        }
      } else if (ip.type == InternetAddressType.IPv6 && bracketed) {
        // Reject IPv4-mapped/compatible aliases and scoped/link-local addresses.
        if (b.take(15).every((v) => v == 0) && b[15] == 1) {
          scope = CandidateScope.loopback;
        } else if ((b[0] & 0xfe) == 0xfc) {
          scope = CandidateScope.privateNetwork;
        }
      }
    } else if (!bracketed && host.length <= 253 && host.contains('.') &&
        !host.endsWith('.localhost') && !host.endsWith('.local') &&
        !host.endsWith('.home.arpa')) {
      final labels = host.split('.');
      final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
      // Do not treat browser-style numeric IPv4 aliases as DNS names.
      final tld = labels.last;
      if (labels.every(label.hasMatch) && RegExp(r'^[a-z]').hasMatch(tld) &&
          !RegExp(r'^0x[0-9a-f]+$').hasMatch(tld)) {
        scope = CandidateScope.publicDomain;
      }
    }
  }
  if (scope == null || (scope == CandidateScope.loopback && port == proxyPort)) return null;
  return LocalAccessCandidate(uri, scope);
}
