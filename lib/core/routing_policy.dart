import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'subscription.dart';

extension RoutingModeLabel on RoutingMode {
  String get label => switch (this) {
    RoutingMode.smart => '智能分流',
    RoutingMode.global => '全局代理',
    RoutingMode.strict => '严格自定义',
  };
}

class RoutingPolicy {
  RoutingPolicy({this.mode = RoutingMode.smart, this.adBlock = true,
      Iterable<String> rules = const []}) : rules = List.unmodifiable(rules) {
    SubscriptionProfile.validateCustomRules(this.rules);
  }
  final RoutingMode mode;
  final bool adBlock;
  final List<String> rules;
  Map<String, dynamic> toJson() =>
      {'version': 1, 'mode': mode.name, 'adBlock': adBlock, 'rules': rules};
  factory RoutingPolicy.fromJson(Map<String, dynamic> raw) {
    if (raw['version'] != 1 || raw['adBlock'] is! bool || raw['rules'] is! List) {
      throw const FormatException('Invalid routing policy');
    }
    return RoutingPolicy(mode: RoutingMode.values.byName(raw['mode'] as String),
        adBlock: raw['adBlock'] as bool,
        rules: (raw['rules'] as List).cast<String>());
  }
}

/// Single writer (strategy editor). A failed write does not change live policy.
class RoutingPolicyStore {
  RoutingPolicyStore({this.file});
  final File? file;
  bool corrupt = false;
  bool get persistent => file != null;
  static Future<RoutingPolicyStore> open() async {
    try {
      final path = await const MethodChannel('clashbrowser/storage/v1')
          .invokeMethod<String>('directory');
      if (path != null && path.isNotEmpty && Directory(path).isAbsolute) {
        return RoutingPolicyStore(file: File('$path/routing-policy-v1.json'));
      }
    } catch (_) {}
    return RoutingPolicyStore();
  }
  Future<RoutingPolicy> restore() async {
    try {
      if (file == null || !await file!.exists()) return RoutingPolicy();
      return RoutingPolicy.fromJson(
          Map<String, dynamic>.from(jsonDecode(await file!.readAsString()) as Map));
    } catch (_) {
      corrupt = true;
      // Never silently broaden a corrupted policy.
      return RoutingPolicy(mode: RoutingMode.strict);
    }
  }
  Future<void> save(RoutingPolicy policy) async {
    if (file == null) return;
    await file!.parent.create(recursive: true);
    final temp = File('${file!.path}.tmp');
    try {
      await temp.writeAsString(jsonEncode(policy.toJson()), flush: true);
      await temp.rename(file!.path);
      corrupt = false;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
