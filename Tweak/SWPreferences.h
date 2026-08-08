#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT NSString * const SWPreferencesChangedNotification;
FOUNDATION_EXPORT NSString * const SWPreferencesDomain;

#ifdef __cplusplus
}
#endif

@interface SWPreferences : NSObject
+ (BOOL)enabled;
+ (BOOL)dismissRequiresDoubleTap;
+ (double)windowScale;
+ (void)setWindowScale:(double)scale;
+ (BOOL)edgeHandleOnLeft;
+ (double)edgeHandleNormalizedY;
+ (void)setEdgeHandleOnLeft:(BOOL)onLeft normalizedY:(double)normalizedY;
+ (NSArray<NSString *> *)selectedBundleIdentifiers;
@end

NS_ASSUME_NONNULL_END
