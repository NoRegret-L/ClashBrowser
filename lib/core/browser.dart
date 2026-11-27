import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_adapter.dart';
import 'native_loopback.dart';
import 'ohos_view.dart';
import 'browser_address.dart';
import 'browser_library.dart';
import 'browser_tabs.dart';

export 'browser_address.dart';

const browserViewType = 'clashbrowser/webview/v2';
const ohosExperimentalJavaScript = bool.fromEnvironment('CLASHBROWSER_OHOS_EXPERIMENTAL_JS');


class BrowserBridge {
  static Future<bool> open(BuildContext context, CoreEndpoint endpoint, {String? policyLabel}) async {
    if (endpoint.username != 'browser' ||
        endpoint.password == null || endpoint.password!.isEmpty) {
      throw StateError('Proxy authentication unavailable');
    }
    final library = await BrowserLibrary.open();
    if (!context.mounted) return false;
    return await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BrowserScreen(endpoint: endpoint, library: library, policyLabel: policyLabel),
    )) ?? false;
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.endpoint, this.library, this.policyLabel});
  final String? policyLabel;
  final BrowserLibrary? library;
  final CoreEndpoint endpoint;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  bool _addressEdited = false;
  bool _nativeExperimentalJavaScript = false;
  bool get _isOhos => Platform.operatingSystem == 'ohos' || Platform.operatingSystem == 'harmonyos';
  MethodChannel? _channel;
  final _tabs = BrowserTabs();
  late final _library = widget.library ?? BrowserLibrary();
  int _generation = 0;
  bool _switching = false;
  bool _navigationFailed = false;
  String? _restoreUrl;
  bool get _canSwitch => !_closing && !_switching && _channel != null && (_ready || _status == '代理不可用，禁止导航');

  Future<void> _switch(void Function() change) async {
    if (!_canSwitch) return;
    setState(() { _switching = true; _ready = false; });
    final old = _channel!;
    try {
      if (await old.invokeMethod<bool>('close') != true) throw StateError('Close failed');
      if (!mounted) return;
      old.setMethodCallHandler(null);
      _channel = null;
      setState(() {
        change();
        _generation++;
        _nativeExperimentalJavaScript = false;
        _restoreUrl = _tabs.active.url;
        _addressEdited = false;
        _address.text = _restoreUrl ?? '';
        _status = '正在配置应用内代理…';
        _switching = false;
        _navigationFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _switching = false;
        _status = '代理不可用，禁止导航';
      });
    }
  }

  Future<void> _saveBookmark() async {
    final url = _tabs.active.url;
    if (url == null || _switching || _closing) return;
    await _library.toggleBookmark(url);
    if (mounted) setState(() {});
  }

  Future<void> _showLibrary(bool favorites) async {
    if (_closing || _switching) return;
    final selected = await showModalBottomSheet<String>(context: context,
      builder: (sheet) => StatefulBuilder(builder: (context, redraw) {
        final urls = favorites ? _library.bookmarks : _library.history.map((v) => v.url).toList();
        return SafeArea(child: Column(children: [
          ListTile(title: Text(favorites ? '收藏夹' : '浏览历史'),
            subtitle: Text(_library.persistent ? '仅保存在本机，不保存查询参数和片段' : '仅当前会话：本地存储不可用'),
            trailing: favorites ? null : TextButton(onPressed: () async {
              await _library.clearHistory();
              if (context.mounted) redraw(() {});
            }, child: const Text('清空历史'))),
          Expanded(child: urls.isEmpty ? const Center(child: Text('暂无记录')) :
            ListView.builder(itemCount: urls.length, itemBuilder: (_, index) {
              final url = urls[index];
              return ListTile(title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: _ready ? () => Navigator.pop(sheet, url) : null,
                trailing: favorites ? IconButton(tooltip: '移除收藏', icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _library.removeBookmark(url);
                    if (context.mounted) redraw(() {});
                  }) : null);
            })),
        ]));
      }));
    if (!mounted) return;
    setState(() {});
    if (selected != null && _ready && !_closing && !_switching) {
      _address.text = selected;
      _go();
    }
  }
  String _status = '正在配置应用内代理…';
  bool _ready = false;
  bool _closing = false;
  bool _allowPop = false;
  late final String _params = jsonEncode({
    'port': widget.endpoint.port,
    'username': widget.endpoint.username,
    'password': widget.endpoint.password,
    'experimentalJavaScript': _isOhos && ohosExperimentalJavaScript,
  });

  void _update(String? state) {
    if (!mounted || _closing || _switching) return;
    setState(() {
      if (state == 'ready') {
        _ready = true;
        _status = '应用内代理 · 实验模式';
      } else if (state == 'pending') {
        _ready = false;
        _status = '正在配置应用内代理…';
      } else if (state == 'failed') {
        _ready = false;
        _status = '代理不可用，禁止导航';
      } else if (state == 'loading') {
        _navigationFailed = false;
        _status = '正在加载网页…';
      } else if (state == 'loadError') {
        _navigationFailed = true;
        _status = '网页加载失败（无直连回退）';
      } else if (state == 'authError') {
        _navigationFailed = true;
        _status = '代理认证失败或不兼容';
      }
    });
    if (state == 'ready' && _restoreUrl != null) {
      final url = _restoreUrl!;
      _restoreUrl = null;
      _command('load', url);
    }
  }

  Future<void> _created(int id, int generation) async {
    final channel = MethodChannel('$browserViewType/$id');
    if (!mounted || generation != _generation || _closing || _switching) {
      try { await channel.invokeMethod<bool>('close'); } catch (_) {}
      return;
    }
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted || generation != _generation || _channel != channel || _closing || _switching) return;
      if (call.method == 'state') _update(call.arguments as String?);
      if (call.method == 'url' && _ready && !_navigationFailed &&
          call.arguments is String && browserAddress(call.arguments as String) != null) {
        final url = call.arguments as String;
        setState(() {
          // A late page-finished callback must never replace a user's draft.
          if (!_addressEdited && !_addressFocus.hasFocus) _address.text = url;
          _tabs.visited(url);
          _status = '网页加载完成 · 应用内代理';
        });
        await _library.record(url);
        if (mounted) setState(() {});
      }
    });
    try {
      if (_isOhos) {
        final mode = await channel.invokeMethod<String>('securityMode');
        if (mounted && generation == _generation && _channel == channel) {
          setState(() => _nativeExperimentalJavaScript = mode == 'experimental-js');
        }
      }
      final state = await channel.invokeMethod<String>('status');
      if (mounted && generation == _generation && _channel == channel) _update(state);
    } catch (_) {
      if (mounted && generation == _generation && _channel == channel) _update('failed');
    }
  }

  Future<void> _command(String method, [String? value]) async {
    if (!_ready || _closing || _switching || _channel == null) return;
    final channel = _channel!;
    if (method != 'stop') _navigationFailed = false;
    try {
      final ok = await channel.invokeMethod<bool>(method, value);
      if (ok != true && mounted && channel == _channel && !_switching) {
        setState(() => _status = '操作未完成或没有可用记录');
      }
    } catch (_) {
      if (channel == _channel) _update('loadError');
    }
  }

  void _go() {
    final url = browserAddress(_address.text);
    if (url == null) {
      setState(() => _status = '仅支持有效的 HTTPS 域名');
      return;
    }
    _addressEdited = false;
    _addressFocus.unfocus();
    _address.text = url.toString();
    setState(() => _status = '正在加载网页…');
    _command('load', url.toString());
  }

  Future<void> _showObservedRoute() async {
    final url = _tabs.active.url;
    if (url == null || _closing || _switching) return;
    final host = Uri.parse(url).host;
    String message = '暂无该域名的原生路由记录';
    try {
      final result = await NativeLoopback.command({'action': 'observedRoute', 'host': host});
      if (result['observed'] == true) {
        final matches = result['matches'] as List;
        message = matches.map((m) => '${m['policy']} · ${m['rule']} · ${m['payload']}').join('\n');
      }
    } catch (_) { message = '原生连接信息不可用'; }
    if (!mounted || _closing || _switching || _tabs.active.url != url) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(host), content: Text('$message\n\n显示当前代理会话最近的真实路由决策，包含已结束连接及 REJECT；不代表请求成功，也不是单个网页的完整流量清单。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  Future<void> _close({bool editPolicy = false}) async {
    if (_closing || _switching) return;
    setState(() { _closing = true; _ready = false; });
    try {
      final channel = _channel;
      if (channel != null && await channel.invokeMethod<bool>('close') != true) {
        throw StateError('Native close not acknowledged');
      }
      await _library.flush();
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(editPolicy);
    } catch (_) {
      if (mounted) setState(() {
        _closing = false;
        _status = '原生视图关闭失败，请重试关闭';
      });
    }
  }

  Widget _surface() {
    final generation = _generation;
    void created(int id) { _created(id, generation); }
    if (Platform.isAndroid) {
      return AndroidView(viewType: browserViewType, creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created);
    }
    if (Platform.isIOS) {
      return UiKitView(viewType: browserViewType, creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created);
    }
    if (Platform.operatingSystem == 'ohos' || Platform.operatingSystem == 'harmonyos') {
      return buildOhosView(browserViewType, _params, created);
    }
    return const Center(child: Text('当前平台不支持浏览器'));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _addressFocus.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('ClashBrowser'),
          actions: [
            if (widget.policyLabel != null) IconButton(tooltip: '切换代理策略：${widget.policyLabel}',
              onPressed: _closing || _switching || _channel == null ? null : () => _close(editPolicy: true), icon: const Icon(Icons.tune)),
            IconButton(tooltip: '当前域名实际命中', onPressed: _closing || _switching || _tabs.active.url == null ? null : _showObservedRoute, icon: const Icon(Icons.route)),
            IconButton(tooltip: '浏览历史', onPressed: _closing || _switching ? null : () => _showLibrary(false), icon: const Icon(Icons.history)),
            IconButton(tooltip: '收藏夹', onPressed: _closing || _switching ? null : () => _showLibrary(true), icon: const Icon(Icons.bookmarks_outlined)),
            IconButton(tooltip: '关闭浏览器',
            onPressed: _closing || _switching ? null : () => _close(), icon: const Icon(Icons.close))],
        ),
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              Expanded(child: SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final tab in _tabs.tabs)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: InputChip(
                    label: Text(tab.url == null ? '新标签页' : Uri.parse(tab.url!).host),
                    selected: tab.id == _tabs.active.id,
                    onPressed: !_canSwitch || tab.id == _tabs.active.id ? null : () => _switch(() => _tabs.activate(tab.id)),
                    onDeleted: !_canSwitch ? null : () {
                      if (tab.id == _tabs.active.id) { _switch(() => _tabs.close(tab.id)); }
                      else { setState(() => _tabs.close(tab.id)); }
                    },
                  )),
              ]))),
              IconButton(tooltip: '新建标签页', onPressed: _canSwitch ? () => _switch(_tabs.add) : null, icon: const Icon(Icons.add)),
            ]),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Expanded(child: TextField(
                  key: const Key('browser-address'), controller: _address,
                  focusNode: _addressFocus,
                  onChanged: (_) => _addressEdited = true,
                  enabled: !_closing, keyboardType: TextInputType.url,
                  autocorrect: false, enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) { if (_ready) _go(); },
                  decoration: const InputDecoration(hintText: 'https://example.com'),
                )),
                IconButton(tooltip: '收藏当前网页', onPressed: _tabs.active.url == null || _switching || _closing ? null : _saveBookmark,
                  icon: Icon(_library.containsBookmark(_tabs.active.url ?? '') ? Icons.star : Icons.star_border)),
                IconButton(tooltip: '打开', onPressed: _ready ? _go : null,
                  icon: const Icon(Icons.arrow_forward)),
              ])),
            Row(children: [
              IconButton(tooltip: '后退', onPressed: _ready ? () => _command('back') : null,
                icon: const Icon(Icons.arrow_back)),
              IconButton(tooltip: '前进', onPressed: _ready ? () => _command('forward') : null,
                icon: const Icon(Icons.arrow_forward)),
              IconButton(tooltip: '刷新', onPressed: _ready ? () => _command('reload') : null,
                icon: const Icon(Icons.refresh)),
              IconButton(tooltip: '停止加载', onPressed: _ready ? () => _command('stop') : null,
                icon: const Icon(Icons.stop)),
              Expanded(child: Text(_status, key: const Key('browser-status'), style: Theme.of(context).textTheme.bodySmall)),
            ]),
            if (_isOhos && ohosExperimentalJavaScript)
              Text(_nativeExperimentalJavaScript
                  ? '实验 JavaScript · 尚未通过真机隔离验证'
                  : 'JavaScript 已关闭 · 原生安全模式不可用',
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 1),
            Expanded(child: KeyedSubtree(key: ValueKey(_generation), child: _surface())),
          ]),
        ),
      ),
    );
  }
}
