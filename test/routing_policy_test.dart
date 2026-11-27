import 'dart:io';
import 'package:clashbrowser/core/routing_policy.dart';
import 'package:clashbrowser/core/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('policy default, ordered custom rules, and strict validation', () {
    expect(RoutingPolicy().mode, RoutingMode.smart);
    expect(SubscriptionProfile.validateCustomRules([
      'DOMAIN,example.com,REJECT',
      'IP-CIDR,203.0.113.0/24,PROXY',
      'IP-CIDR6,2001:db8::/32,DIRECT',
    ]), ['DOMAIN,example.com,REJECT',
      'IP-CIDR,203.0.113.0/24,BROWSER-PROXY,no-resolve',
      'IP-CIDR6,2001:db8::/32,DIRECT,no-resolve']);
    for (final rule in ['MATCH,x,DIRECT','DOMAIN,x.com,UNKNOWN',
      'IP-CIDR,2001:db8::/32,DIRECT','IP-CIDR6,2001:db8::/129,DIRECT',
      'IP-CIDR,203.0.113.0/24,DIRECT,no-resolve']) {
      expect(() => RoutingPolicy(rules: [rule]), throwsFormatException);
    }
  });
  test('policy saved atomically, restored, corrupt file fails closed', () async {
    final dir = await Directory.systemTemp.createTemp();
    try {
      final file = File('${dir.path}/policy.json');
      final policy = RoutingPolicy(mode: RoutingMode.global, adBlock: false,
          rules: ['DOMAIN,example.com,REJECT']);
      await RoutingPolicyStore(file: file).save(policy);
      final store = RoutingPolicyStore(file: file);
      final restored = await store.restore();
      expect(restored.toJson(), policy.toJson());
      await file.writeAsString('corrupt');
      expect((await store.restore()).mode, RoutingMode.strict);
      expect(store.corrupt, true);
      expect(await file.readAsString(), 'corrupt');
    } finally { await dir.delete(recursive: true); }
  });
}
