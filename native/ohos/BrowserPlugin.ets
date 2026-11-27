import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import common from '@ohos.app.ability.common';
import { webview } from '@kit.ArkWeb';

const VIEW_TYPE: string = 'clashbrowser/webview/v2';

class BrowserArgs {
  port: number = 0;
  username: string = '';
  password: string = '';
}

export class BrowserPlugin implements FlutterPlugin {
  private storage: MethodChannel | undefined;
  getUniqueClassName(): string { return 'ClashBrowserPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const directory = binding.getApplicationContext().filesDir;
    this.storage = new MethodChannel(binding.getBinaryMessenger(), 'clashbrowser/storage/v1');
    this.storage.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'directory') result.success(directory);
        else result.notImplemented();
      }
    });
    binding.getPlatformViewRegistry().registerViewFactory(VIEW_TYPE,
      new BrowserFactory(binding.getBinaryMessenger()));
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.storage?.setMethodCallHandler(null);
    this.storage = undefined;
  }
}

class BrowserFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  constructor(messenger: BinaryMessenger) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
  }
  create(context: common.Context, viewId: number, args: ESObject): PlatformView {
    return new BrowserView(viewId, args as string, this.messenger);
  }
}

@Observed
class BrowserView extends PlatformView {
  controller: webview.WebviewController = new webview.WebviewController();
  private channel: MethodChannel;
  state: string = 'pending';
  closed: boolean = false;
  private args: BrowserArgs = new BrowserArgs();
  private authAttempted: boolean = false;
  constructor(id: number, args: string, messenger: BinaryMessenger) {
    super();
    this.channel = new MethodChannel(messenger, VIEW_TYPE + '/' + id);
    try {
      this.args = JSON.parse(args) as BrowserArgs;
      if (!Number.isInteger(this.args.port) || this.args.port < 1 || this.args.port > 65535 ||
          this.args.username !== 'browser' || !/^[a-f0-9]{64}$/.test(this.args.password)) {
        this.state = 'failed';
      }
    } catch (_) { this.state = 'failed'; }
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      }
    });
  }
  safe(value: string): boolean {
    return /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+(?::[0-9]+)?(?:[\/?#]|$)/i.test(value)
      && !/^https:\/\/[0-9.]+(?::[0-9]+)?(?:[\/?#]|$)/.test(value)
      && !/\.localhost(?::[0-9]+)?(?:[\/?#]|$)/i.test(value);
  }
  private emit(value: string): void {
    if (value === 'ready' || value === 'pending' || value === 'failed') this.state = value;
    if (!this.closed) this.channel.invokeMethod('state', value);
  }
  configure(): void {
    if (this.closed || this.state !== 'pending') return;
    try {
      const config = new webview.ProxyConfig();
      config.insertProxyRule('http://127.0.0.1:' + this.args.port, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
      config.clearImplicitRules();
      webview.ProxyController.applyProxyOverride(config, () => {
        if (!this.closed) this.emit('ready');
      });
    } catch (_) { this.emit('failed'); }
  }
  private handle(call: MethodCall, result: MethodResult): void {
    if (call.method === 'status') { result.success(this.state); return; }
    if (call.method === 'close') { this.close(); result.success(true); return; }
    if (this.closed || this.state !== 'ready') { result.success(false); return; }
    try {
      switch (call.method) {
        case 'load':
          const url = call.args as string;
          if (!this.safe(url)) { result.success(false); return; }
          this.authAttempted = false;
          this.controller.loadUrl(url); break;
        case 'back':
          if (!this.controller.accessBackward()) { result.success(false); return; }
          this.controller.backward(); break;
        case 'forward':
          if (!this.controller.accessForward()) { result.success(false); return; }
          this.controller.forward(); break;
        case 'reload':
          if (!this.safe(this.controller.getUrl())) { result.success(false); return; }
          this.authAttempted = false;
          this.controller.refresh(); break;
        case 'stop': this.controller.stop(); break;
        default: result.notImplemented(); return;
      }
      result.success(true);
    } catch (_) { result.success(false); }
  }
  auth(event: OnHttpAuthRequestEvent): boolean {
    if (this.closed || this.state !== 'ready' || this.authAttempted ||
        (event.host !== '127.0.0.1' && event.host !== '127.0.0.1:' + this.args.port) ||
        event.realm !== '') {
      event.handler.cancel(); this.emit('authError'); return false;
    }
    this.authAttempted = true;
    return event.handler.confirm(this.args.username, this.args.password);
  }
  loaded(url: string): void {
    if (!this.closed && this.safe(url)) this.channel.invokeMethod('url', url);
  }
  loadError(): void { this.emit('loadError'); }
  private close(): void {
    if (this.closed) return;
    this.closed = true; this.state = 'failed';
    try { this.controller.stop(); } catch (_) {}
    this.args.password = ''; this.args.username = '';
    // Retain the proxy override while the renderer drains.
  }
  getView(): WrappedBuilder<[Params]> { return wrapBuilder(BrowserBuilder); }
  dispose(): void { this.close(); this.channel.setMethodCallHandler(null); }
}

@Component
struct BrowserContent {
  @Prop params: Params;
  private browser: BrowserView = this.params.platformView as BrowserView;

  build() {
    Web({ src: 'about:blank', controller: this.browser.controller })
      .javaScriptAccess(false)
      .fileAccess(false)
      .domStorageAccess(false)
      .mixedMode(MixedMode.None)
      .onControllerAttached(() => { this.browser.configure(); })
      .onLoadIntercept((event) => {
        if (!event) return true;
        const url = event.data.getRequestUrl();
        return url !== 'about:blank' &&
          (this.browser.closed || this.browser.state !== 'ready' || !this.browser.safe(url));
      })
      .onHttpAuthRequest((event) => {
        if (!event) return false;
        return this.browser.auth(event);
      })
      .onPermissionRequest((event) => { event?.request.deny(); })
      .onSslErrorEventReceive((event) => { event?.handler.handleCancel(); })
      .onPageEnd((event) => { if (event) this.browser.loaded(event.url); })
      .onErrorReceive((event) => {
        if (event?.request.isMainFrame()) this.browser.loadError();
      })
      .width('100%').height('100%')
  }
}

@Builder
function BrowserBuilder(params: Params) {
  BrowserContent({ params: params })
}
