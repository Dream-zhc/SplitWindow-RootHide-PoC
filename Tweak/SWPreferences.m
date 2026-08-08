#import "SWPreferences.h"

NSString * const SWPreferencesChangedNotification = @"com.dream.splitwindow/preferencesChanged";
NSString * const SWPreferencesDomain = @"com.dream.splitwindow";

@implementation SWPreferences

+ (id)copyPreferenceForKey:(NSString *)key {
    CFStringRef domain = (__bridge CFStringRef)SWPreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain));
}

+ (BOOL)enabled {
    // Do not inherit the legacy Enabled value. A previous crashing build may
    // have left it set to true even after the package was removed.
    id value = [self copyPreferenceForKey:@"EnabledV040"];
    // Fail closed. The tweak must never create SpringBoard windows merely because
    // it was installed or because SpringBoard restarted after a crash.
    return value == nil ? NO : [value boolValue];
}

+ (BOOL)dismissRequiresDoubleTap {
    id value = [self copyPreferenceForKey:@"DismissRequiresDoubleTap"];
    return value == nil ? NO : [value boolValue];
}

+ (double)windowScale {
    id value = [self copyPreferenceForKey:@"WindowScale"];
    double scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.72;
    return MIN(0.95, MAX(0.32, scale));
}

+ (void)setWindowScale:(double)scale {
    scale = MIN(0.95, MAX(0.32, scale));
    CFStringRef domain = (__bridge CFStringRef)SWPreferencesDomain;
    CFPreferencesSetAppValue(CFSTR("WindowScale"),
                             (__bridge CFPropertyListRef)@(scale),
                             domain);
    CFPreferencesAppSynchronize(domain);
}

+ (BOOL)edgeHandleOnLeft {
    id value = [self copyPreferenceForKey:@"EdgeHandleOnLeft"];
    return value == nil ? NO : [value boolValue];
}

+ (double)edgeHandleNormalizedY {
    id value = [self copyPreferenceForKey:@"EdgeHandleNormalizedY"];
    double normalized = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.48;
    return MIN(0.90, MAX(0.10, normalized));
}

+ (void)setEdgeHandleOnLeft:(BOOL)onLeft normalizedY:(double)normalizedY {
    normalizedY = MIN(0.90, MAX(0.10, normalizedY));
    CFStringRef domain = (__bridge CFStringRef)SWPreferencesDomain;
    CFPreferencesSetAppValue(CFSTR("EdgeHandleOnLeft"),
                             (__bridge CFPropertyListRef)@(onLeft),
                             domain);
    CFPreferencesSetAppValue(CFSTR("EdgeHandleNormalizedY"),
                             (__bridge CFPropertyListRef)@(normalizedY),
                             domain);
    CFPreferencesAppSynchronize(domain);
}

+ (NSArray<NSString *> *)selectedBundleIdentifiers {
    id value = [self copyPreferenceForKey:@"SelectedApps"];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *valid = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
                [valid addObject:item];
            }
        }
        if (valid.count > 0) return valid.copy;
    }

    // Safe defaults so the first install can be tested before opening Settings.
    return @[@"com.apple.calculator", @"com.apple.mobilenotes"];
}

@end
