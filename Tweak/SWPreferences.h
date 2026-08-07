#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SWPreferencesChangedNotification;
FOUNDATION_EXPORT NSString * const SWPreferencesDomain;

@interface SWPreferences : NSObject
+ (BOOL)enabled;
+ (BOOL)showFloatingButton;
+ (NSArray<NSString *> *)selectedBundleIdentifiers;
@end

NS_ASSUME_NONNULL_END
