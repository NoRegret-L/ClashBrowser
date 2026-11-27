#import "BrowserScreen.h"
#import <WebKit/WebKit.h>
#import <Network/Network.h>

@interface CBBrowserScreen () <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UITextField *address;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,copy) FlutterResult closed;
@property(nonatomic,assign) NSInteger port;
@property(nonatomic,copy) NSString *user;
@property(nonatomic,copy) NSString *password;
@end

@implementation CBBrowserScreen
- (instancetype)initWithPort:(NSInteger)port user:(NSString *)user password:(NSString *)password closed:(FlutterResult)closed {
    if ((self = [super init])) {
        _port = port; _user = [user copy]; _password = [password copy]; _closed = [closed copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}
- (BOOL)safeURL:(NSURL *)url {
    NSString *host = url.host;
    return [url.scheme.lowercaseString isEqualToString:@"https"] && !url.user &&
        [host containsString:@"."] && [host rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound &&
        ![host.lowercaseString hasSuffix:@".localhost"];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.address = [[UITextField alloc] init];
    self.address.placeholder = @"https://example.com";
    self.address.keyboardType = UIKeyboardTypeURL;
    self.address.autocapitalizationType = UITextAutocapitalizationTypeNone;
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem]; [go setTitle:@"打开" forState:UIControlStateNormal]; [go addTarget:self action:@selector(loadPage) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"关闭" forState:UIControlStateNormal]; [close addTarget:self action:@selector(closePage) forControlEvents:UIControlEventTouchUpInside];
    self.status = [[UILabel alloc] init]; self.status.text = @"实验模式 · 无直连回退";
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    config.defaultWebpagePreferences.allowsContentJavaScript = NO;
    NSString *port = [NSString stringWithFormat:@"%ld", (long)self.port];
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", port.UTF8String);
    nw_proxy_config_t proxy = nw_proxy_config_create_http_connect(endpoint, NULL);
    if (proxy) {
        nw_proxy_config_set_username_and_password(proxy, self.user.UTF8String, self.password.UTF8String);
        nw_proxy_config_set_failover_allowed(proxy, false);
        config.websiteDataStore.proxyConfigurations = @[proxy];
        self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        self.web.navigationDelegate = self;
        self.web.UIDelegate = self;
    } else { go.enabled = NO; self.status.text = @"代理配置失败"; }
    self.user = nil; self.password = nil;
    UIStackView *bar = [[UIStackView alloc] initWithArrangedSubviews:@[self.address, go, close]];
    bar.axis = UILayoutConstraintAxisHorizontal; bar.spacing = 8;
    [go setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [close setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIView *body = self.web ?: [[UIView alloc] init];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[bar, self.status, body]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8]
    ]];
}
- (void)loadPage {
    [self.address resignFirstResponder];
    NSString *raw = [self.address.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![raw containsString:@"://"]) raw = [@"https://" stringByAppendingString:raw ?: @""];
    NSURL *url = [NSURL URLWithString:raw];
    if (self.web && [self safeURL:url]) [self.web loadRequest:[NSURLRequest requestWithURL:url]];
    else self.status.text = @"仅支持 HTTPS 域名";
}
- (void)closePage {
    [self.web stopLoading]; self.web.navigationDelegate = nil;
    [self.web removeFromSuperview]; self.web = nil;
    FlutterResult done = self.closed; self.closed = nil;
    [self dismissViewControllerAnimated:YES completion:^{ if (done) done(@YES); }];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    decisionHandler([self safeURL:action.request.URL] && action.targetFrame != nil ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.status.text = @"网页加载失败（无直连回退）";
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.address.text = webView.URL.absoluteString;
}
@end
