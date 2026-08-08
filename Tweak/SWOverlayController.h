#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SWOverlayController : NSObject
+ (instancetype)sharedInstance;
- (void)start;
- (void)reloadPreferences;
- (void)setSystemLocked:(BOOL)locked;
- (void)frontDisplayDidChange:(nullable id)newDisplay;
@end

NS_ASSUME_NONNULL_END
