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
  } else {
    result(FlutterMethodNotImplemented);
  }
}
@end
