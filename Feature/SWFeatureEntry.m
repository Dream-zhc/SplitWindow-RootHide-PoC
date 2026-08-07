#import "SWOverlayController.h"
#import "SWPreferences.h"
#import <Foundation/Foundation.h>

static void SWStartFeature(void) {
    SWOverlayController *controller = [SWOverlayController sharedInstance];
    [controller start];
}

static void SWReloadFeaturePreferences(void) {
    [[SWOverlayController sharedInstance] reloadPreferences];
}

__attribute__((visibility("default")))
void SWFeatureStart(void) {
    if ([NSThread isMainThread]) {
        SWStartFeature();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            SWStartFeature();
        });
    }
}

__attribute__((visibility("default")))
void SWFeatureReload(void) {
    if ([NSThread isMainThread]) {
        SWReloadFeaturePreferences();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            SWReloadFeaturePreferences();
        });
    }
}
