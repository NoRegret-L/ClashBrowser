import 'package:flutter/material.dart';

import 'core/subscription.dart';
import 'core/native_probe.dart';
import 'core/core_adapter.dart';
import 'core/subscription_link.dart';
import 'core/browser.dart';

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
  final _url = TextEditingController();
  final _proxyDomains = TextEditingController();
  final _directDomains = TextEditingController();
  final _core = ChannelCoreAdapter();
  bool _downloading = false;
  bool _changingCore = false;
  bool _openingBrowser = false;
  CoreEndpoint? _endpoint;

  Future<void> _openBrowser() async {
    final endpoint = _endpoint;
    if (endpoint == null || _core.state != CoreState.listenerReady || _openingBrowser) return;
    setState(() { _openingBrowser = true; _error = null; });
    try {
      await BrowserBridge.open(endpoint);
    } catch (_) {
      if (mounted) setState(() => _error = '浏览器打开失败：原生代理未就绪或不兼容。');
    } finally {
      if (mounted) setState(() => _openingBrowser = false);
    }
  }
  bool get _locked => _changingCore || _core.state != CoreState.offline;

  Future<void> _download() async {
    setState(() { _downloading = true; _error = null; });
    try {
      final profile = await SubscriptionLink.fetch(_url.text);
      if (!mounted) return;
      setState(() {
        _profiles.add(profile);
        _active = _profiles.length - 1;
        _selected = profile.nodeNames.first;
        _url.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '订阅下载失败：请检查 HTTPS 链接及 Clash 格式。');
    } finally { if (mounted) setState(() => _downloading = false); }
  }

  List<String> _domains(String value) => value.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();

  Future<void> _toggleCore() async {
    setState(() { _changingCore = true; _error = null; });
    try {
      if (_core.state == CoreState.offline) {
        _endpoint = await _core.start(_profiles[_active!], selectedNode: _selected!,
          proxyDomains: _domains(_proxyDomains.text), directDomains: _domains(_directDomains.text));
      } else {
        _endpoint = null;
        await _core.stop();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '内核操作失败，网页保持禁用。');
    } finally { if (mounted) setState(() => _changingCore = false); }
  }
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
    _url.dispose();
    _proxyDomains.dispose();
    _directDomains.dispose();
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
            if (_core.state != CoreState.listenerReady)
              const Text('代理未就绪 · 浏览器网络已禁用')
            else ...[
              const Text('本地代理已启动 · 浏览器实验模式（仅 HTTPS，JavaScript 关闭）'),
              const Text('需真机验证代理认证及流量隔离；不要用于敏感会话。'),
              FilledButton(onPressed: _openingBrowser || _changingCore ? null : _openBrowser,
                child: const Text('打开实验浏览器')),
            ],
            OutlinedButton(
              onPressed: _probing ? null : _probe,
              child: const Text('检查原生内核'),
            ),
            if (_nativeStatus != null) Text(_nativeStatus!),
            const SizedBox(height: 16),
            const Text('仅导入 Clash YAML 中的节点，不应用原订阅规则或网络设置。'),
            const Text('仅保存在当前会话。订阅下载由你主动触发，使用直连 HTTPS，不经过浏览器代理。'),
            TextField(controller: _url, enabled: !_locked && !_downloading,
              obscureText: true, autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Clash HTTPS 订阅链接')),
            FilledButton(onPressed: _locked || _downloading ? null : _download,
              child: Text(_downloading ? '下载中' : '从链接导入')),
            TextField(
              key: const Key('yaml-input'),
              controller: _yaml,
              enabled: !_locked && !_downloading,
              minLines: 3,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '粘贴 Clash YAML'),
            ),
            FilledButton(onPressed: _locked || _downloading ? null : _import, child: const Text('导入节点')),
            if (_error != null) Text(_error!),
            if (profile != null) ...[
              DropdownButton<int>(
                value: _active,
                isExpanded: true,
                items: [
                  for (var i = 0; i < _profiles.length; i++)
                    DropdownMenuItem(value: i, child: Text('配置 ${i + 1}')),
                ],
                onChanged: _locked || _downloading ? null : (i) {
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
                onChanged: _locked || _downloading ? null : (name) => setState(() => _selected = name),
              ),
              OutlinedButton(onPressed: _locked || _downloading ? null : _remove, child: const Text('删除配置')),
              TextField(controller: _proxyDomains, enabled: !_locked,
                decoration: const InputDecoration(labelText: '代理域名（逗号分隔）')),
              TextField(controller: _directDomains, enabled: !_locked,
                decoration: const InputDecoration(labelText: '直连域名（逗号分隔）')),
              FilledButton(onPressed: _changingCore || _downloading || _openingBrowser ? null : _toggleCore,
                child: Text(_core.state == CoreState.offline ? '启动本地代理' : '停止本地代理')),
            ],
          ],
        ),
      ),
    );
  }
}
