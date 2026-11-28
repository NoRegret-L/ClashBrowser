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
  FlutterMethodChannel *storage = [FlutterMethodChannel methodChannelWithName:@"clashbrowser/storage/v1" binaryMessenger:[registrar messenger]];
  [storage setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    if (![call.method isEqualToString:@"directory"]) { result(FlutterMethodNotImplemented); return; }
    NSURL *dir = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    if (dir) result(dir.path);
    else result([FlutterError errorWithCode:@"STORAGE" message:@"App storage unavailable" details:nil]);
  }];
  [registrar registerViewFactory:[[CBBrowserFactory alloc] initWithMessenger:[registrar messenger]] withId:@"clashbrowser/webview/v2"];
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
