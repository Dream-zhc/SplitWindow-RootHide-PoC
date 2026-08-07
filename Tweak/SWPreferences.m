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

+ (BOOL)showFloatingButton {
    id value = [self copyPreferenceForKey:@"ShowFloatingButton"];
    return value == nil ? YES : [value boolValue];
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
