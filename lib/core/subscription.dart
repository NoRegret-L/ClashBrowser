import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Import only a deliberately supported subset of Clash nodes.
/// The source document is never sent to the native core.
enum RoutingMode { strict, smart, global }


class SubscriptionProfile {
  SubscriptionProfile._(this._nodes, this.ignoredSections);

  final Map<String, String> _nodes;
  final List<String> ignoredSections;

  List<String> get nodeNames => List.unmodifiable(_nodes.keys);

  static const _common = {
    'name', 'type', 'server', 'port', 'udp', 'tls', 'servername',
    'sni', 'skip-cert-verify', 'client-fingerprint',
  };
  static const _protocolFields = <String, Set<String>>{
    'http': {'username', 'password'},
    'socks5': {'username', 'password'},
    'ss': {'cipher', 'password'},
    'trojan': {'password', 'network', 'ws-opts'},
    'vmess': {'uuid', 'alterId', 'cipher', 'network', 'ws-opts'},
    'vless': {'uuid', 'flow', 'network', 'ws-opts', 'reality-opts'},
  };
  static const _reservedNames = {
    'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE',
    'GLOBAL', 'BROWSER-PROXY',
  };

  factory SubscriptionProfile.parse(String source) {
    // Do not include parser error contents (may contain subscription secrets).
    dynamic document;
    try {
      document = loadYaml(source);
    } catch (_) {
      throw const FormatException('Invalid YAML');
    }
    if (document is! Map || document['proxies'] is! List) {
      throw const FormatException('Expected a Clash proxies list');
    }
    final rawNodes = document['proxies'] as List;
    final nodes = <String, String>{};
    for (final raw in rawNodes) {
      if (raw is! Map) {
        throw const FormatException('Invalid node structure');
      }
      final type = raw['type'];
      final name = raw['name'];
      final server = raw['server'];
      final port = raw['port'];
      if (type is! String || !_protocolFields.containsKey(type) ||
          name is! String || name.trim().isEmpty ||
          name.contains(RegExp(r'[,\x00-\x1f]')) ||
          _reservedNames.contains(name.toUpperCase()) ||
          server is! String || server.trim().isEmpty ||
          server.contains(RegExp(r'[\s/\\\x00-\x1f]')) ||
          port is! int || port < 1 || port > 65535) {
        throw const FormatException('Unsupported or invalid node');
      }
      if (nodes.containsKey(name)) {
        throw const FormatException('Duplicate node name');
      }
      final node = <String, dynamic>{};
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            !(_common.contains(key) || _protocolFields[type]!.contains(key))) {
          throw const FormatException('Unsupported node option');
        }
        if (key == 'skip-cert-verify' && value != false) {
          throw const FormatException('Insecure TLS verification option');
        }
        if (key == 'network' && value != 'tcp' && value != 'ws') {
          throw const FormatException('Unsupported transport');
        }
        if (key == 'ws-opts' || key == 'reality-opts') {
          node[key] = _transportOptions(key, value);
        } else if (value is String || value is bool || value is int) {
          node[key] = value;
        } else {
          throw const FormatException('Invalid node option');
        }
      }
      for (final key in ['udp', 'tls']) {
        if (node.containsKey(key) && node[key] is! bool) {
          throw const FormatException('Invalid boolean option');
        }
      }
      if (node.containsKey('alterId') && node['alterId'] is! int) {
        throw const FormatException('Invalid alterId');
      }
      for (final key in [
        'username', 'password', 'cipher', 'uuid', 'flow', 'servername',
        'sni', 'client-fingerprint',
      ]) {
        if (node.containsKey(key) && node[key] is! String) {
          throw const FormatException('Invalid text option');
        }
      }
      if (const {'ss', 'trojan'}.contains(type) &&
          (node['password'] is! String || (node['password'] as String).isEmpty)) {
        throw const FormatException('Missing node credential');
      }
      if (const {'vmess', 'vless'}.contains(type) &&
          (node['uuid'] is! String || (node['uuid'] as String).isEmpty)) {
        throw const FormatException('Missing node UUID');
      }
      if (type == 'ss' && (node['cipher'] is! String ||
          (node['cipher'] as String).isEmpty)) {
        throw const FormatException('Missing cipher');
      }
      // Immutable serialized copy, not a mutable YAML alias.
      nodes[name] = jsonEncode(node);
    }
    if (nodes.isEmpty) {
      throw const FormatException('No supported nodes');
    }
    // Import is explicitly node-only. Do not expose arbitrary key strings,
    // which could themselves be sensitive; report recognized section names.
    final ignored = <String>[
      for (final key in [
        'rules', 'proxy-groups', 'proxy-providers', 'rule-providers',
        'tun', 'dns', 'listeners', 'external-controller',
      ])
        if (document.containsKey(key)) key,
    ];
    if (document.keys.any((key) => key != 'proxies' && !ignored.contains(key))) {
      ignored.add('other-settings');
    }
    return SubscriptionProfile._(Map.unmodifiable(nodes), List.unmodifiable(ignored));
  }

  static Map<String, dynamic> _transportOptions(String key, dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid transport options');
    }
    final out = <String, dynamic>{};
    final allowed = key == 'ws-opts'
        ? {'path', 'headers'}
        : {'public-key', 'short-id'};
    for (final entry in value.entries) {
      final field = entry.key;
      final item = entry.value;
      if (field is! String || !allowed.contains(field)) {
        throw const FormatException('Unsupported transport option');
      }
      if (field == 'headers') {
        if (item is! Map ||
            item.entries.any((e) => e.key is! String || e.value is! String)) {
          throw const FormatException('Invalid WebSocket headers');
        }
        out[field] = Map<String, String>.from(item);
      } else if (item is String) {
        out[field] = item;
      } else {
        throw const FormatException('Invalid transport option');
      }
    }
    return out;
  }

  /// Native code must allocate the loopback port and revalidate before start.
  /// Native smart mode adds only trusted built-in providers. The explicit
  /// strict mode retains the original fail-closed rule projection.
  String buildConfig({
    required String selectedNode,
    RoutingMode routingMode = RoutingMode.strict,
    bool adBlock = true,
    Iterable<String> customRules = const [],
    Iterable<String> proxyDomains = const [],
    Iterable<String> directDomains = const [],
  }) {
    final node = _nodes[selectedNode];
    if (node == null) {
      throw const FormatException('Unknown selected node');
    }
    final proxy = _domains(proxyDomains);
    final direct = _domains(directDomains);
    for (final a in proxy) {
      for (final b in direct) {
        if (a == b || a.endsWith('.$b') || b.endsWith('.$a')) {
          throw const FormatException('Overlapping proxy and direct rules');
        }
      }
    }
    return jsonEncode({
      'routingMode': routingMode.name,
      'adBlock': adBlock,
      'allow-lan': false,
      'bind-address': '127.0.0.1',
      'mode': 'rule',
      'log-level': 'warning',
      'find-process-mode': 'off',
      'tun': {'enable': false},
      'dns': {'enable': false},
      'profile': {'store-selected': false, 'store-fake-ip': false},
      'proxies': [jsonDecode(node)],
      'proxy-groups': [
        {'name': 'BROWSER-PROXY', 'type': 'select', 'proxies': [selectedNode]},
      ],
      'rules': [
        ...validateCustomRules(customRules),
        for (final d in direct) 'DOMAIN-SUFFIX,$d,DIRECT',
        for (final d in proxy) 'DOMAIN-SUFFIX,$d,BROWSER-PROXY',
        'MATCH,REJECT',
      ],
    });
  }

  /// Ordered first-match rules, limited to the four supported types.
  static List<String> validateCustomRules(Iterable<String> input) {
    final result = <String>[];
    for (final line in input) {
      final p = line.split(',').map((v) => v.trim()).toList();
      if (p.length != 3) throw const FormatException('Expected TYPE,target,policy');
      final type = p[0].toUpperCase();
      final target = p[1].toLowerCase();
      final action = p[2].toUpperCase() == 'PROXY' ? 'BROWSER-PROXY' : p[2].toUpperCase();
      if (!{'DIRECT', 'BROWSER-PROXY', 'REJECT'}.contains(action)) {
        throw const FormatException('Invalid rule action');
      }
      if (type == 'DOMAIN' || type == 'DOMAIN-SUFFIX') {
        _domains([target]);
        result.add('$type,$target,$action');
      } else if (type == 'IP-CIDR' || type == 'IP-CIDR6') {
        final parts = target.split('/');
        final address = parts.length == 2 ? InternetAddress.tryParse(parts[0]) : null;
        final bits = parts.length == 2 ? int.tryParse(parts[1]) : null;
        final family = type == 'IP-CIDR' ? InternetAddressType.IPv4 : InternetAddressType.IPv6;
        if (address == null || address.type != family || parts[0].contains('%') ||
            bits == null || bits < 0 || bits > (family == InternetAddressType.IPv4 ? 32 : 128) ||
            !RegExp(r'^[0-9]+$').hasMatch(parts[1])) {
          throw const FormatException('Invalid IP prefix');
        }
        result.add('$type,$target,$action,no-resolve');
      } else {
        throw const FormatException('Unsupported rule type');
      }
    }
    return result;
  }

  static Set<String> _domains(Iterable<String> input) {
    final result = <String>{};
    final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    for (final raw in input) {
      final domain = raw.trim().toLowerCase();
      if (domain.length > 253 || !domain.contains('.') ||
          !domain.split('.').every(label.hasMatch)) {
        throw const FormatException('Invalid domain suffix');
      }
      result.add(domain);
    }
    return result;
  }
}
