#import "SWOverlayController.h"
#import "SWPreferences.h"
#import "SWLogger.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP SWOriginalFrontDisplayDidChange = NULL;

static BOOL SWFeatureIsUILocked(void) {
    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    id manager = nil;
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if ([managerClass respondsToSelector:sharedSelector]) {
        manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    }
    if (!manager) return YES;

    for (NSString *selectorName in @[@"isUILocked", @"isLocked", @"isLockScreenVisible"]) {
        SEL selector = NSSelectorFromString(selectorName);
        NSMethodSignature *signature = [manager methodSignatureForSelector:selector];
        if (![manager respondsToSelector:selector] || !signature ||
            signature.numberOfArguments != 2 || signature.methodReturnLength != sizeof(BOOL)) continue;
        return ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector);
    }
    // Fail closed: if this iOS build exposes none of the expected selectors,
    // do not construct SpringBoard overlay UI automatically at lock screen.
    return YES;
}

static void SWHookedFrontDisplayDidChange(id self, SEL _cmd, id newDisplay) {
    if (SWOriginalFrontDisplayDidChange) {
        ((void (*)(id, SEL, id))SWOriginalFrontDisplayDidChange)(self, _cmd, newDisplay);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SWOverlayController sharedInstance] frontDisplayDidChange:newDisplay];
    });
}

static void SWInstallFrontDisplayObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class springBoardClass = NSClassFromString(@"SpringBoard");
        SEL selector = NSSelectorFromString(@"frontDisplayDidChange:");
        Method method = NULL;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(springBoardClass, &methodCount);
        for (unsigned int index = 0; index < methodCount; index++) {
            if (method_getName(methods[index]) == selector) {
                method = methods[index];
                break;
            }
        }
        free(methods);
        if (!method) {
            SWFileLog(@"HOOK frontDisplayDidChange unavailable");
            return;
        }
        const char *types = method_getTypeEncoding(method);
        unsigned int argumentCount = method_getNumberOfArguments(method);
        if (argumentCount != 3 || !types) {
            SWFileLog(@"HOOK frontDisplayDidChange rejected unexpected signature");
            return;
        }
        char returnType[16] = {0};
        method_getReturnType(method, returnType, sizeof(returnType));
        char argumentType[16] = {0};
        method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
        if (returnType[0] != 'v' || argumentType[0] != '@') {
            SWFileLog(@"HOOK frontDisplayDidChange rejected unexpected signature");
            return;
        }
        IMP current = method_getImplementation(method);
        if (!current || current == (IMP)SWHookedFrontDisplayDidChange) return;
        SWOriginalFrontDisplayDidChange = current;
        method_setImplementation(method, (IMP)SWHookedFrontDisplayDidChange);
        SWFileLog(@"HOOK frontDisplayDidChange installed");
    });
}

static void SWStartFeature(void) {
    SWOverlayController *controller = [SWOverlayController sharedInstance];
    BOOL locked = SWFeatureIsUILocked();
    [controller setSystemLocked:locked];
    if (locked) {
        SWFileLog(@"START deferred while lock screen active");
        return;
    }
    SWInstallFrontDisplayObserver();
    [controller start];
    [controller setSystemLocked:NO];
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
