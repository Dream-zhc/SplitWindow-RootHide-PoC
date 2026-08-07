#import "SWOverlayController.h"
#import "SWPreferences.h"
#import "SWLogger.h"
#import <Foundation/Foundation.h>

static void SWPreferencesChanged(__unused CFNotificationCenterRef center,
                                 __unused void *observer,
                                 __unused CFStringRef name,
                                 __unused const void *object,
                                 __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL enabled = [SWPreferences enabled];
        SWFileLog(@"PREF notification received enabled=%d", enabled);
        SWOverlayController *controller = [SWOverlayController sharedInstance];
        if (enabled) {
            // This is the only path that starts the overlay. There is deliberately
            // no SpringBoard launch hook: after a crash/restart the tweak stays
            // passive until Settings posts this notification again.
            [controller start];
        }
        [controller reloadPreferences];
    });
}

%ctor {
    @autoreleasepool {
        SWFileLog(@"BOOT dylib loaded; passive start enabled (no automatic UIWindow creation)");
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    SWPreferencesChanged,
                                    (__bridge CFStringRef)SWPreferencesChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
