#import "SWOverlayController.h"
#import "SWPreferences.h"
#import <Foundation/Foundation.h>

static void SWApplyFeaturePreferences(void) {
    SWOverlayController *controller = [SWOverlayController sharedInstance];
    if ([SWPreferences enabled]) {
        [controller start];
    }
    [controller reloadPreferences];
}

__attribute__((visibility("default")))
void SWFeatureStart(void) {
    if ([NSThread isMainThread]) {
        SWApplyFeaturePreferences();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            SWApplyFeaturePreferences();
        });
    }
}

__attribute__((visibility("default")))
void SWFeatureReload(void) {
    if ([NSThread isMainThread]) {
        SWApplyFeaturePreferences();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            SWApplyFeaturePreferences();
        });
    }
}
