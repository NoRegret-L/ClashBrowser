#import "ClashbrowserIosProbePlugin.h"
#import <Clash/Clash.objc.h>

@implementation ClashbrowserIosProbePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"clashbrowser/native_probe/v1"
                                  binaryMessenger:[registrar messenger]];
  ClashbrowserIosProbePlugin *instance = [[ClashbrowserIosProbePlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
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
