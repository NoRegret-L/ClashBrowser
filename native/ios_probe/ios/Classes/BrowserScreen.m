#import "BrowserScreen.h"
#import <WebKit/WebKit.h>
#import <Network/Network.h>

static NSString *const CBViewType = @"clashbrowser/webview/v2";

@interface CBBrowserView : NSObject<FlutterPlatformView, WKNavigationDelegate, WKUIDelegate>
@property(nonatomic,strong) UIView *container;
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) FlutterMethodChannel *channel;
@property(nonatomic,assign) BOOL ready;
@property(nonatomic,assign) BOOL closed;
@property(nonatomic,assign) NSInteger proxyPort;
@property(nonatomic,copy) NSString *proxyUser;
@property(nonatomic,copy) NSString *proxyPassword;
- (instancetype)initWithFrame:(CGRect)frame identifier:(int64_t)identifier arguments:(id)args messenger:(NSObject<FlutterBinaryMessenger> *)messenger;
@end

@implementation CBBrowserView
- (BOOL)safeURL:(NSURL *)url {
    NSString *host = url.host;
    return [url.scheme.lowercaseString isEqualToString:@"https"] && !url.user &&
        [host rangeOfString:@"^[a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)+$" options:NSRegularExpressionSearch].location != NSNotFound &&
        [host rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound &&
        ![host.lowercaseString hasSuffix:@".localhost"];
}
- (instancetype)initWithFrame:(CGRect)frame identifier:(int64_t)identifier arguments:(id)args messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    if (!(self = [super init])) return nil;
    _container = [[UIView alloc] initWithFrame:frame];
    _channel = [FlutterMethodChannel methodChannelWithName:[NSString stringWithFormat:@"%@/%lld", CBViewType, identifier] binaryMessenger:messenger];
    __weak CBBrowserView *weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        CBBrowserView *view = weakSelf;
        if (!view) { result(@NO); return; }
        [view handle:call result:result];
    }];
    if (![args isKindOfClass:NSString.class]) return self;
    id decoded = [NSJSONSerialization JSONObjectWithData:[args dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![decoded isKindOfClass:NSDictionary.class]) return self;
    NSDictionary *params = decoded;
    NSNumber *port = params[@"port"]; NSString *user = params[@"username"]; NSString *pass = params[@"password"];
    if (![port isKindOfClass:NSNumber.class] || port.integerValue < 1 || port.integerValue > 65535 ||
        ![user isKindOfClass:NSString.class] || ![user isEqualToString:@"browser"] ||
        ![pass isKindOfClass:NSString.class] ||
        [pass rangeOfString:@"^[a-f0-9]{64}$" options:NSRegularExpressionSearch].location == NSNotFound) return self;
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    config.defaultWebpagePreferences.allowsContentJavaScript = NO;
    NSString *portText = port.stringValue;
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", portText.UTF8String);
    nw_proxy_config_t proxy = nw_proxy_config_create_http_connect(endpoint, NULL);
    if (!proxy) return self;
    _proxyPort = port.integerValue;
    _proxyUser = [user copy]; _proxyPassword = [pass copy];
    nw_proxy_config_set_username_and_password(proxy, user.UTF8String, pass.UTF8String);
    nw_proxy_config_set_failover_allowed(proxy, false);
    config.websiteDataStore.proxyConfigurations = @[proxy];
    _web = [[WKWebView alloc] initWithFrame:_container.bounds configuration:config];
    _web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _web.navigationDelegate = self; _web.UIDelegate = self;
    [_container addSubview:_web];
    _ready = YES;
    return self;
}
- (UIView *)view { return self.container; }
- (void)handle:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"status"]) { result(self.ready && !self.closed ? @"ready" : @"failed"); return; }
    if ([call.method isEqualToString:@"close"]) { [self close]; result(@YES); return; }
    if (!self.ready || self.closed) { result(@NO); return; }
    if ([call.method isEqualToString:@"load"]) {
        NSURL *url = [call.arguments isKindOfClass:NSString.class] ? [NSURL URLWithString:call.arguments] : nil;
        if (![self safeURL:url]) { result(@NO); return; }
        [self.web loadRequest:[NSURLRequest requestWithURL:url]];
    } else if ([call.method isEqualToString:@"back"]) {
        if (!self.web.canGoBack) { result(@NO); return; } [self.web goBack];
    } else if ([call.method isEqualToString:@"forward"]) {
        if (!self.web.canGoForward) { result(@NO); return; } [self.web goForward];
    } else if ([call.method isEqualToString:@"reload"]) {
        if (![self safeURL:self.web.URL]) { result(@NO); return; } [self.web reload];
    } else if ([call.method isEqualToString:@"stop"]) {
        [self.web stopLoading];
    } else { result(FlutterMethodNotImplemented); return; }
    result(@YES);
}
- (void)close {
    self.ready = NO; self.closed = YES;
    self.proxyUser = nil; self.proxyPassword = nil;
    [self.web stopLoading]; self.web.navigationDelegate = nil; self.web.UIDelegate = nil;
    [self.web removeFromSuperview]; self.web = nil;
}
- (void)dealloc { [self close]; [self.channel setMethodCallHandler:nil]; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    decisionHandler(!self.closed && self.ready && [self safeURL:action.request.URL] && action.targetFrame != nil ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if ([space isProxy]) {
        // Only a Basic challenge from this exact local proxy receives credentials.
        // A platform that does not expose the proxy challenge still fails closed.
        if (self.ready && !self.closed && challenge.previousFailureCount == 0 &&
            [space.host isEqualToString:@"127.0.0.1"] && space.port == self.proxyPort &&
            [space.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic] &&
            self.proxyUser.length && self.proxyPassword.length) {
            NSURLCredential *credential = [NSURLCredential credentialWithUser:self.proxyUser password:self.proxyPassword persistence:NSURLCredentialPersistenceNone];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        } else {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
            if (!self.closed) [self.channel invokeMethod:@"state" arguments:@"authError"];
        }
        return;
    }
    // Preserve normal platform trust verification; never give local proxy credentials to a website.
    if ([space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (!self.closed) [self.channel invokeMethod:@"state" arguments:@"loadError"];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (!self.closed && [self safeURL:webView.URL]) [self.channel invokeMethod:@"url" arguments:webView.URL.absoluteString];
}
@end

@interface CBBrowserFactory ()
@property(nonatomic,strong) NSObject<FlutterBinaryMessenger> *messenger;
@end
@implementation CBBrowserFactory
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    if ((self = [super init])) _messenger = messenger;
    return self;
}
- (NSObject<FlutterMessageCodec> *)createArgsCodec { return [FlutterStandardMessageCodec sharedInstance]; }
- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame viewIdentifier:(int64_t)viewId arguments:(id)args {
    return [[CBBrowserView alloc] initWithFrame:frame identifier:viewId arguments:args messenger:self.messenger];
}
@end
