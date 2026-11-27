import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_adapter.dart';
import 'ohos_view.dart';

const browserViewType = 'clashbrowser/webview/v2';

/// The native view independently enforces this restriction for navigations.
Uri? browserAddress(String value) {
  var text = value.trim();
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      !RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$').hasMatch(uri.host) ||
      !RegExp(r'[a-zA-Z]').hasMatch(uri.host) ||
      uri.host.toLowerCase().endsWith('.localhost')) return null;
  return uri;
}

class BrowserBridge {
  static Future<void> open(BuildContext context, CoreEndpoint endpoint) async {
    if (endpoint.username != 'browser' ||
        endpoint.password == null || endpoint.password!.isEmpty) {
      throw StateError('Proxy authentication unavailable');
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => BrowserScreen(endpoint: endpoint),
    ));
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.endpoint});
  final CoreEndpoint endpoint;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _address = TextEditingController();
  MethodChannel? _channel;
  String _status = '正在配置应用内代理…';
  bool _ready = false;
  bool _closing = false;
  bool _allowPop = false;
  late final String _params = jsonEncode({
    'port': widget.endpoint.port,
    'username': widget.endpoint.username,
    'password': widget.endpoint.password,
  });

  void _update(String? state) {
    if (!mounted || _closing) return;
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
      } else if (state == 'loadError') {
        _status = '网页加载失败（无直连回退）';
      } else if (state == 'authError') {
        _status = '代理认证失败或不兼容';
      }
    });
  }

  Future<void> _created(int id) async {
    if (!mounted) return;
    final channel = MethodChannel('$browserViewType/$id');
    _channel = channel;
    if (_closing) {
      try { await channel.invokeMethod<bool>('close'); } catch (_) {}
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'state') _update(call.arguments as String?);
      if (call.method == 'url' && mounted && !_closing &&
          call.arguments is String && browserAddress(call.arguments as String) != null) {
        _address.text = call.arguments as String;
      }
    });
    try {
      _update(await channel.invokeMethod<String>('status'));
    } catch (_) {
      _update('failed');
    }
  }

  Future<void> _command(String method, [String? value]) async {
    if (!_ready || _closing || _channel == null) return;
    try {
      final ok = await _channel!.invokeMethod<bool>(method, value);
      if (ok != true && mounted) {
        setState(() => _status = '操作未完成或没有可用记录');
      }
    } catch (_) {
      _update('loadError');
    }
  }

  void _go() {
    final url = browserAddress(_address.text);
    if (url == null) {
      setState(() => _status = '仅支持有效的 HTTPS 域名');
      return;
    }
    FocusScope.of(context).unfocus();
    _address.text = url.toString();
    _command('load', url.toString());
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() { _closing = true; _ready = false; });
    try {
      final channel = _channel;
      if (channel != null && await channel.invokeMethod<bool>('close') != true) {
        throw StateError('Native close not acknowledged');
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() {
        _closing = false;
        _status = '原生视图关闭失败，请重试关闭';
      });
    }
  }

  Widget _surface() {
    if (Platform.isAndroid) {
      return AndroidView(viewType: browserViewType, creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created);
    }
    if (Platform.isIOS) {
      return UiKitView(viewType: browserViewType, creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created);
    }
    if (Platform.operatingSystem == 'ohos' || Platform.operatingSystem == 'harmonyos') {
      return buildOhosView(browserViewType, _params, _created);
    }
    return const Center(child: Text('当前平台不支持浏览器'));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
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
          actions: [IconButton(tooltip: '关闭浏览器',
            onPressed: _closing ? null : _close, icon: const Icon(Icons.close))],
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Expanded(child: TextField(
                  key: const Key('browser-address'), controller: _address,
                  enabled: !_closing, keyboardType: TextInputType.url,
                  autocorrect: false, enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) { if (_ready) _go(); },
                  decoration: const InputDecoration(hintText: 'https://example.com'),
                )),
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
              Expanded(child: Text(_status, style: Theme.of(context).textTheme.bodySmall)),
            ]),
            const Divider(height: 1),
            Expanded(child: _surface()),
          ]),
        ),
      ),
    );
  }
}
