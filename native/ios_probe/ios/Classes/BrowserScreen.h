#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

@interface CBBrowserScreen : UIViewController
- (instancetype)initWithPort:(NSInteger)port user:(NSString *)user password:(NSString *)password closed:(FlutterResult)closed;
@end
