#import <Foundation/Foundation.h>

@interface SWOverlayController : NSObject
+ (instancetype)sharedInstance;
- (void)start;
- (void)reloadPreferences;
@end
