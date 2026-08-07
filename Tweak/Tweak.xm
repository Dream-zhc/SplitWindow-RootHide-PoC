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
    // Keep SpringBoard's injection path minimal: no synchronous file I/O,
    // preferences reads, UIWindow creation, or FrontBoard work in the ctor.
    NSLog(@"[SplitWindow] loader attached; passive mode");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    SWPreferencesChanged,
                                    (__bridge CFStringRef)SWPreferencesChangedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // Persist a breadcrumb only after SpringBoard has survived startup.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SWFileLog(@"BOOT-OK SpringBoard survived 8s after SplitWindow injection; overlay still passive");
    });
}
