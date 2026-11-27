#import "ClashbrowserIosProbePlugin.h"
#import <Clash/Clash.objc.h>
#import "BrowserScreen.h"

@implementation ClashbrowserIosProbePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"clashbrowser/native_probe/v1"
                                  binaryMessenger:[registrar messenger]];
  ClashbrowserIosProbePlugin *instance = [[ClashbrowserIosProbePlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  FlutterMethodChannel *browser = [FlutterMethodChannel methodChannelWithName:@"clashbrowser/browser/v1" binaryMessenger:[registrar messenger]];
  [browser setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    if (![call.method isEqualToString:@"open"] || ![call.arguments isKindOfClass:NSDictionary.class]) { result(FlutterMethodNotImplemented); return; }
    NSDictionary *args = call.arguments;
    NSNumber *port = args[@"port"]; NSString *user = args[@"username"]; NSString *pass = args[@"password"];
    UIViewController *host = registrar.viewController;
    if (![port isKindOfClass:NSNumber.class] || port.integerValue < 1 || port.integerValue > 65535 ||
        ![user isKindOfClass:NSString.class] || ![user isEqualToString:@"browser"] ||
        ![pass isKindOfClass:NSString.class] || !pass.length || !host || host.presentedViewController) {
      result([FlutterError errorWithCode:@"UNAVAILABLE" message:@"Proxy not available" details:nil]); return;
    }
    CBBrowserScreen *screen = [[CBBrowserScreen alloc] initWithPort:port.integerValue user:user password:pass closed:result];
    [host presentViewController:screen animated:YES completion:nil];
  }];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"version"]) {
    result(ClashVersion());
  } else if ([call.method isEqualToString:@"loopback"] && [call.arguments isKindOfClass:[NSString class]]) {
    NSString *input = [call.arguments copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSString *reply = ClashBrowserLoopback(input);
      dispatch_async(dispatch_get_main_queue(), ^{ result(reply); });
    });
  } else {
    result(FlutterMethodNotImplemented);
  }
}
@end
