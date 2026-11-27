import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { BrowserSession } from '../entryability/BrowserPlugin';

@Entry
@Component
struct BrowserPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State address: string = '';
  @State ready: boolean = false;
  @State status: string = '正在配置应用内代理…';
  private closed: boolean = false;
  private authAttempted: boolean = false;

  private safe(value: string): boolean {
    return /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+(?::[0-9]+)?(?:[\/?#]|$)/i.test(value)
      && !/^https:\/\/[0-9.]+(?::[0-9]+)?(?:[\/?#]|$)/.test(value)
      && !/\.localhost(?::[0-9]+)?(?:[\/?#]|$)/i.test(value);
  }

  private configure(): void {
    if (!BrowserSession.result) return;
    try {
      const config = new webview.ProxyConfig();
      config.insertProxyRule('http://127.0.0.1:' + BrowserSession.port, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
      config.clearImplicitRules();
      webview.ProxyController.applyProxyOverride(config, () => {
        if (!this.closed) { this.ready = true; this.status = '代理配置已应用 · 实验模式'; }
      });
    } catch (_) { this.status = '代理配置失败，网页保持禁用'; }
  }

  aboutToDisappear(): void {
    this.closed = true;
    this.ready = false;
    try { this.controller.stop(); } catch (_) {}
    // Do not remove the override while the web engine may still be draining.
    BrowserSession.close();
  }

  build() {
    Column() {
      Row() {
        TextInput({ text: this.address, placeholder: 'https://example.com' })
          .onChange((value: string) => { this.address = value; }).layoutWeight(1)
        Button('打开').enabled(this.ready).onClick(() => {
          let url = this.address.trim();
          if (!url.includes('://')) url = 'https://' + url;
          if (this.ready && this.safe(url)) {
            this.authAttempted = false;
            this.controller.loadUrl(url);
          } else { this.status = '仅支持 HTTPS 域名'; }
        })
        Button('关闭').onClick(() => { router.back(); })
      }.width('100%')
      Text(this.status)
      Web({ src: 'about:blank', controller: this.controller })
        .javaScriptAccess(false)
        .fileAccess(false)
        .domStorageAccess(false)
        .mixedMode(MixedMode.None)
        .onControllerAttached(() => { this.configure(); })
        .onLoadIntercept((event) => {
          if (!event) return true;
          const url = event.data.getRequestUrl();
          return url !== 'about:blank' && (!this.ready || !this.safe(url));
        })
        .onHttpAuthRequest((event) => {
          if (!event) return false;
          if (!this.ready || this.authAttempted ||
              (event.host !== '127.0.0.1' && event.host !== '127.0.0.1:' + BrowserSession.port) ||
              event.realm !== '') {
            event.handler.cancel();
            this.status = '认证失败或不兼容';
            return false;
          }
          this.authAttempted = true;
          return event.handler.confirm(BrowserSession.user, BrowserSession.password);
        })
        .onPermissionRequest((event) => { event?.request.deny(); })
        .onSslErrorEventReceive((event) => { event?.handler.handleCancel(); })
        .onErrorReceive((event) => {
          if (event?.request.isMainFrame()) this.status = '网页加载失败（无直连回退）';
        })
        .layoutWeight(1).width('100%')
    }.height('100%').width('100%')
  }
}
