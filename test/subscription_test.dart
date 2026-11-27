import 'dart:convert';

import 'package:clashbrowser/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

const fixture = '''
proxies:
  - name: Test
    type: ss
    server: proxy.example
    port: 443
    cipher: aes-128-gcm
    password: fake
tun: {enable: true, auto-route: true}
allow-lan: true
external-controller: 0.0.0.0:9090
rules: [MATCH,DIRECT]
''';

void main() {
  test('projects nodes and replaces all network settings', () {
    final p = SubscriptionProfile.parse(fixture);
    expect(p.nodeNames, ['Test']);
    expect(p.ignoredSections, containsAll(['tun', 'rules', 'external-controller']));
    final c = jsonDecode(p.buildConfig(
      selectedNode: 'Test',
      proxyDomains: ['example.com'],
      directDomains: ['local.example'],
    )) as Map;
    expect(c['allow-lan'], false);
    expect(c['bind-address'], '127.0.0.1');
    expect(c['tun'], {'enable': false});
    expect(c.containsKey('external-controller'), false);
    expect(c.containsKey('mixed-port'), false);
    expect(c['rules'], ['DOMAIN-SUFFIX,local.example,DIRECT',
      'DOMAIN-SUFFIX,example.com,BROWSER-PROXY', 'MATCH,REJECT']);
  });
  test('rejects duplicate names, unsupported options and insecure TLS', () {
    for (final text in [
      'proxies: [{name: DIRECT, type: http, server: x, port: 80}]',
      'proxies: [{name: x, type: http, server: x, port: 80, interface-name: wlan0}]',
      'proxies: [{name: x, type: http, server: x, port: 80, skip-cert-verify: true}]',
      'proxies: [{name: x, type: http, server: x, port: 80}, {name: x, type: http, server: x, port: 80}]',
      'proxies: [{name: x, type: http, server: x, port: 80, port: 81}]',
      'proxies: [{name: x, type: http, server: x, port: 0}]',
    ]) {
      expect(() => SubscriptionProfile.parse(text), throwsFormatException);
    }
  });
  test('default rejects and domain injection/overlap rejected', () {
    final p = SubscriptionProfile.parse(fixture);
    expect(jsonDecode(p.buildConfig(selectedNode: 'Test'))['rules'], ['MATCH,REJECT']);
    expect(() => p.buildConfig(selectedNode: 'missing'), throwsFormatException);
    expect(() => p.buildConfig(selectedNode: 'Test',
      proxyDomains: ['x.com,DIRECT']), throwsFormatException);
    expect(() => p.buildConfig(selectedNode: 'Test',
      proxyDomains: ['example.com'], directDomains: ['a.example.com']),
      throwsFormatException);
  });
}
