#import "SWRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

@interface SWAppListController : UITableViewController
@end

static NSString * const SWPrefsDomain = @"com.dream.splitwindow";
static NSString * const SWActivationNotification = @"com.dream.splitwindow/activationRequested";
static NSString * const SWPreferencesNotification = @"com.dream.splitwindow/preferencesChanged";

@implementation SWRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)postDarwinNotification:(NSString *)name {
    if (name.length == 0) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL,
                                         NULL,
                                         YES);
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    CFStringRef domain = (__bridge CFStringRef)SWPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    if (!value) return defaultValue;

    BOOL result = defaultValue;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    }
    CFRelease(value);
    return result;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *domain = [specifier propertyForKey:@"defaults"];
    NSString *key = [specifier propertyForKey:@"key"];
    if (domain.length > 0 && key.length > 0) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)domain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    }

    if ([key isEqualToString:@"EnabledV040"] && [value boolValue]) {
        [self postDarwinNotification:SWActivationNotification];
    } else {
        [self postDarwinNotification:SWPreferencesNotification];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self boolPreferenceForKey:@"EnabledV040" defaultValue:NO]) {
        [self postDarwinNotification:SWActivationNotification];
    }
}

- (void)activateSplitWindow {
    [self postDarwinNotification:SWActivationNotification];
}

- (void)showAppPicker {
    Class controllerClass = NSClassFromString(@"SWAppListController");
    if (!controllerClass) return;
    UIViewController *controller = [controllerClass new];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
