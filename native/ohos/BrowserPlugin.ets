import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { router } from '@kit.ArkUI';

export class BrowserSession {
  static port: number = 0;
  static user: string = '';
  static password: string = '';
  static result: MethodResult | undefined = undefined;

  static close(): void {
    const done = BrowserSession.result;
    BrowserSession.result = undefined;
    BrowserSession.port = 0;
    BrowserSession.user = '';
    BrowserSession.password = '';
    if (done) done.success(true);
  }
}

export class BrowserPlugin implements FlutterPlugin {
  private channel: MethodChannel | undefined;
  getUniqueClassName(): string { return 'ClashBrowserPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'clashbrowser/browser/v1');
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        if (call.method !== 'open') { result.notImplemented(); return; }
        const port = call.argument('port') as number;
        const user = call.argument('username') as string;
        const pass = call.argument('password') as string;
        if (BrowserSession.result || !Number.isInteger(port) || port < 1 || port > 65535 ||
            user !== 'browser' || !pass) {
          result.error('UNAVAILABLE', 'Proxy not available', null); return;
        }
        BrowserSession.port = port;
        BrowserSession.user = user;
        BrowserSession.password = pass;
        BrowserSession.result = result;
        router.pushUrl({ url: 'pages/BrowserPage' }).catch(() => {
          BrowserSession.result = undefined;
          BrowserSession.port = 0;
          BrowserSession.user = '';
          BrowserSession.password = '';
          result.error('UNAVAILABLE', 'Cannot open browser', null);
        });
      }
    });
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
  }
}
