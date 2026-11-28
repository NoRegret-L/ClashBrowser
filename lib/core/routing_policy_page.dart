import 'package:flutter/material.dart';
import 'routing_policy.dart';
import 'subscription.dart';

class RoutingPolicyPage extends StatefulWidget {
  const RoutingPolicyPage({super.key, required this.policy, required this.store});
  final RoutingPolicy policy;
  final RoutingPolicyStore store;
  @override
  State<RoutingPolicyPage> createState() => _RoutingPolicyPageState();
}

class _RoutingPolicyPageState extends State<RoutingPolicyPage> {
  late RoutingMode _mode = widget.policy.mode;
  late bool _ads = widget.policy.adBlock;
  late final _rules = TextEditingController(text: widget.policy.rules.join('\n'));
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final policy = RoutingPolicy(mode: _mode, adBlock: _ads,
          rules: _rules.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty));
      await widget.store.save(policy);
      if (mounted) Navigator.pop(context, policy);
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = '规则格式无效或保存失败，原策略不变。';
      });
    }
  }
  @override
  void dispose() { _rules.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(appBar: AppBar(title: const Text('代理策略')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!widget.store.persistent) const Text('本地存储不可用：仅当前会话'),
        if (widget.store.corrupt) const Text('旧配置无法读取，已回退严格模式；保存将替换损坏配置。'),
        for (final mode in RoutingMode.values)
          ListTile(title: Text(mode.label), leading: Icon(_mode == mode
              ? Icons.radio_button_checked : Icons.radio_button_off),
            subtitle: Text(switch (mode) {
              RoutingMode.smart => '国内直连，其他走代理',
              RoutingMode.global => '默认代理；保留广告拦截和私网安全门禁',
              RoutingMode.strict => '仅自定义规则，未匹配拒绝',
            }),
            onTap: _saving ? null : () => setState(() => _mode = mode)),
        SwitchListTile(title: const Text('内置广告拦截'),
            value: _ads, onChanged: _saving || _mode == RoutingMode.strict
                ? null : (v) => setState(() => _ads = v)),
        const Text('自定义规则（按行优先匹配）'),
        TextField(key: const Key('policy-rules'), controller: _rules,
          enabled: !_saving, minLines: 4, maxLines: 10, autocorrect: false,
          decoration: const InputDecoration(hintText: 'DOMAIN,example.com,PROXY\nDOMAIN-SUFFIX,example.org,REJECT\nIP-CIDR,203.0.113.0/24,PROXY\nIP-CIDR6,2001:db8::/32,PROXY')),
        const Text('仅允许 DOMAIN / DOMAIN-SUFFIX / IP-CIDR / IP-CIDR6 和 DIRECT / PROXY / REJECT。IP 规则不主动 DNS 解析。局域网兼容待第三阶段。'),
        if (_error != null) Text(_error!),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('保存并应用')),
      ])));
}
