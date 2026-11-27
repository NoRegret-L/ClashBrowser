import 'package:flutter/material.dart';

import 'core/subscription.dart';
import 'core/native_probe.dart';

void main() => runApp(const ClashBrowser());

class ClashBrowser extends StatelessWidget {
  const ClashBrowser({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ClashBrowser',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const SubscriptionScreen(),
  );
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _yaml = TextEditingController();
  final _profiles = <SubscriptionProfile>[];
  int? _active;
  String? _selected;
  String? _error;
  String? _nativeStatus;
  bool _probing = false;

  Future<void> _probe() async {
    setState(() => _probing = true);
    final result = await NativeCoreProbe.inspect();
    if (!mounted) return;
    setState(() {
      _nativeStatus = result;
      _probing = false;
    });
  }

  @override
  void dispose() {
    _yaml.dispose();
    super.dispose();
  }

  void _import() {
    try {
      final profile = SubscriptionProfile.parse(_yaml.text);
      setState(() {
        _profiles.add(profile);
        _active = _profiles.length - 1;
        _selected = profile.nodeNames.first;
        _error = null;
        _yaml.clear();
      });
    } on FormatException {
      setState(() => _error = '导入失败：格式、节点类型或选项不受支持。');
    }
  }

  void _remove() {
    final active = _active;
    if (active == null) return;
    setState(() {
      _profiles.removeAt(active);
      _active = _profiles.isEmpty ? null : 0;
      _selected = _profiles.isEmpty ? null : _profiles.first.nodeNames.first;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _active == null ? null : _profiles[_active!];
    return Scaffold(
      appBar: AppBar(title: const Text('ClashBrowser')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('代理未就绪 · 浏览器网络已禁用'),
            OutlinedButton(
              onPressed: _probing ? null : _probe,
              child: const Text('检查原生内核'),
            ),
            if (_nativeStatus != null) Text(_nativeStatus!),
            const SizedBox(height: 16),
            const Text('仅导入 Clash YAML 中的节点，不应用原订阅规则或网络设置。'),
            const Text('仅保存在当前会话，暂不支持订阅 URL 下载。'),
            TextField(
              key: const Key('yaml-input'),
              controller: _yaml,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '粘贴 Clash YAML'),
            ),
            FilledButton(onPressed: _import, child: const Text('导入节点')),
            if (_error != null) Text(_error!),
            if (profile != null) ...[
              DropdownButton<int>(
                value: _active,
                isExpanded: true,
                items: [
                  for (var i = 0; i < _profiles.length; i++)
                    DropdownMenuItem(value: i, child: Text('配置 ${i + 1}')),
                ],
                onChanged: (i) {
                  if (i == null) return;
                  setState(() {
                    _active = i;
                    _selected = _profiles[i].nodeNames.first;
                  });
                },
              ),
              Text('已导入 ${profile.nodeNames.length} 个节点'),
              if (profile.ignoredSections.isNotEmpty)
                const Text('已忽略原订阅的非节点设置；不会自动启用任何规则。'),
              DropdownButton<String>(
                key: const Key('node-select'),
                value: _selected,
                isExpanded: true,
                items: [
                  for (final name in profile.nodeNames)
                    DropdownMenuItem(value: name, child: Text(name,
                      overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (name) => setState(() => _selected = name),
              ),
              OutlinedButton(onPressed: _remove, child: const Text('删除配置')),
            ],
          ],
        ),
      ),
    );
  }
}
