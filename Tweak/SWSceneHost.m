#import "SWSceneHost.h"
#import "SWLogger.h"
#import <objc/message.h>
#import <objc/runtime.h>

static id SWMsg0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static id SWMsg1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

static void SWVoid0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void SWVoid1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

static void SWVoid2(id obj, SEL sel, id a, id b) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(obj, sel, a, b);
}

static void SWVoidBool(id obj, SEL sel, BOOL value) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
}

@interface SWSceneHost ()
@property (nonatomic, copy, readwrite, nullable) NSString *bundleIdentifier;
@property (nonatomic, strong, readwrite, nullable) id scene;
@property (nonatomic, strong, readwrite, nullable) id presenter;
@property (nonatomic, strong, nullable) UIView *fallbackHostView;
@property (nonatomic) NSUInteger openGeneration;
@end

@implementation SWSceneHost

- (id)sceneManager {
    Class managerClass = NSClassFromString(@"FBSceneManager");
    id manager = SWMsg0(managerClass, NSSelectorFromString(@"sharedInstance"));
    return manager;
}

- (id)springBoardApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    id controller = SWMsg0(controllerClass, NSSelectorFromString(@"sharedInstance"));
    if (!controller) return nil;

    id app = SWMsg1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    if (!app) app = SWMsg1(controller, NSSelectorFromString(@"applicationWithDisplayIdentifier:"), bundleIdentifier);
    return app;
}

- (BOOL)object:(id)object containsBundleIdentifier:(NSString *)bundleIdentifier {
    if (!object || bundleIdentifier.length == 0) return NO;
    return [[object description] rangeOfString:bundleIdentifier options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (BOOL)scene:(id)scene matchesBundleIdentifier:(NSString *)bundleIdentifier {
    if (!scene) return NO;
    if ([self object:scene containsBundleIdentifier:bundleIdentifier]) return YES;

    for (NSString *path in @[@"identifier",
                             @"settings.identifier",
                             @"settings.persistentIdentifier",
                             @"clientProcess.bundleIdentifier",
                             @"clientProcess.identity.embeddedApplicationIdentifier",
                             @"clientProcess.identity.applicationIdentifier",
                             @"definition.clientIdentity.bundleIdentifier"]) {
        @try {
            id value = [scene valueForKeyPath:path];
            if ([self object:value containsBundleIdentifier:bundleIdentifier]) return YES;
        } @catch (__unused NSException *exception) {}
    }
    return NO;
}

- (id)sceneFromCollection:(id)collection bundleIdentifier:(NSString *)bundleIdentifier {
    if (!collection) return nil;
    if ([collection isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = collection;
        for (id key in dictionary) {
            id candidate = dictionary[key];
            if ([self object:key containsBundleIdentifier:bundleIdentifier] ||
                [self scene:candidate matchesBundleIdentifier:bundleIdentifier]) {
                return candidate;
            }
        }
        return nil;
    }

    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id candidate in collection) {
            if ([self scene:candidate matchesBundleIdentifier:bundleIdentifier]) return candidate;
        }
    }
    return nil;
}

- (id)sceneForBundleIdentifier:(NSString *)bundleIdentifier {
    // SpringBoard already owns the authoritative SBApplication -> mainScene
    // mapping. Use it first instead of guessing opaque FBScene identifiers.
    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    id mainScene = SWMsg0(application, NSSelectorFromString(@"mainScene"));
    if (mainScene) return mainScene;

    id manager = [self sceneManager];
    if (!manager) return nil;

    // Konban-era FBSceneManager exposes a deterministic scene identifier helper.
    // Prefer it on iOS 16; only fall back to dictionary scanning if unavailable.
    id sceneIdentifier = SWMsg1(manager, NSSelectorFromString(@"_createSceneIdentifierForApplicationID:"), bundleIdentifier);
    if (sceneIdentifier) {
        id directScene = SWMsg1(manager, NSSelectorFromString(@"sceneWithIdentifier:"), sceneIdentifier);
        if (directScene) return directScene;
    }

    id scenes = nil;
    @try {
        id value = [manager valueForKey:@"_scenesByID"];
        if (value) scenes = value;
    } @catch (__unused NSException *exception) {}

    if (!scenes) {
        @try {
            id value = [manager valueForKey:@"scenesByID"];
            if (value) scenes = value;
        } @catch (__unused NSException *exception) {}
    }

    if (sceneIdentifier && [scenes isKindOfClass:[NSDictionary class]]) {
        id directScene = [(NSDictionary *)scenes objectForKey:sceneIdentifier];
        if (directScene) return directScene;
    }

    id scanned = [self sceneFromCollection:scenes bundleIdentifier:bundleIdentifier];
    if (scanned) return scanned;

    // FBSceneWorkspace on newer iOS builds may expose a collection through
    // `scenes` while the old `_scenesByID` ivar is absent or opaque.
    id workspaceScenes = SWMsg0(manager, NSSelectorFromString(@"scenes"));
    scanned = [self sceneFromCollection:workspaceScenes bundleIdentifier:bundleIdentifier];
    if (scanned) return scanned;

    return nil;
}

- (void)launchSuspended:(NSString *)bundleIdentifier {
    UIApplication *application = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(application, selector, bundleIdentifier, YES);
        SWFileLog(@"SCENE-2 launch requested %@ suspended=1", bundleIdentifier);
        return;
    }
    SWFileLog(@"SCENE-2 launch selector unavailable");
}

- (void)setScene:(id)scene foreground:(BOOL)foreground {
    if (!scene) return;

    id settings = SWMsg0(scene, NSSelectorFromString(@"mutableSettings"));
    if (!settings) {
        @try { settings = [[scene valueForKey:@"settings"] mutableCopy]; }
        @catch (__unused NSException *exception) {}
    }
    if (!settings) return;

    SWVoidBool(settings, NSSelectorFromString(@"setForeground:"), foreground);
    SWVoidBool(settings, NSSelectorFromString(@"setBackgrounded:"), !foreground);

    SEL update3 = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    if ([scene respondsToSelector:update3]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, update3, settings, nil, nil);
        return;
    }

    SEL update2 = NSSelectorFromString(@"updateSettings:withTransitionContext:");
    if ([scene respondsToSelector:update2]) {
        SWVoid2(scene, update2, settings, nil);
    }
}

- (UIView *)modernPresentationViewForScene:(id)scene {
    id manager = SWMsg0(scene, NSSelectorFromString(@"uiPresentationManager"));
    if (!manager) return nil;

    NSString *identifier = [NSString stringWithFormat:@"com.dream.splitwindow.%@.%@",
                            self.bundleIdentifier ?: @"app", NSUUID.UUID.UUIDString];
    id presenter = SWMsg1(manager, NSSelectorFromString(@"createPresenterWithIdentifier:"), identifier);
    if (!presenter) return nil;

    SWVoid0(presenter, NSSelectorFromString(@"activate"));
    UIView *view = SWMsg0(presenter, NSSelectorFromString(@"presentationView"));
    if (![view isKindOfClass:[UIView class]]) {
        SWVoid0(presenter, NSSelectorFromString(@"deactivate"));
        SWVoid0(presenter, NSSelectorFromString(@"invalidate"));
        return nil;
    }

    self.presenter = presenter;
    SWFileLog(@"HOST-4 modern presenter active %@", self.bundleIdentifier);
    return view;
}

- (UIView *)legacyLayerHostViewForScene:(id)scene {
    Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    if (!hostClass) return nil;

    id host = nil;
    SEL describedInit = NSSelectorFromString(@"initWithScene:debugDescription:");
    if ([hostClass instancesRespondToSelector:describedInit]) {
        host = ((id (*)(id, SEL, id, id))objc_msgSend)([hostClass alloc],
                                                       describedInit,
                                                       scene,
                                                       @"SplitWindow");
    } else {
        SEL initSelector = NSSelectorFromString(@"initWithScene:");
        if (![hostClass instancesRespondToSelector:initSelector]) return nil;
        host = ((id (*)(id, SEL, id))objc_msgSend)([hostClass alloc], initSelector, scene);
    }
    if (![host isKindOfClass:[UIView class]]) return nil;

    Class contextClass = NSClassFromString(@"UIScenePresentationContext");
    SEL contextInit = NSSelectorFromString(@"_initWithDefaultValues");
    if (contextClass && [contextClass instancesRespondToSelector:contextInit]) {
        id context = ((id (*)(id, SEL))objc_msgSend)([contextClass alloc], contextInit);
        SWVoid1(host, NSSelectorFromString(@"_setPresentationContext:"), context);
    }

    self.fallbackHostView = host;
    SWFileLog(@"HOST-4 legacy layer host active %@", self.bundleIdentifier);
    return host;
}

- (void)finishOpenForScene:(id)scene generation:(NSUInteger)generation completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    self.scene = scene;
    SWFileLog(@"SCENE-3 foreground begin %@ scene=%@", self.bundleIdentifier, scene);
    [self setScene:scene foreground:YES];

    UIView *hostedView = [self modernPresentationViewForScene:scene];
    if (!hostedView) hostedView = [self legacyLayerHostViewForScene:scene];

    if (!hostedView) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"No supported Scene presentation API was available."}];
        SWFileLog(@"HOST-4 failed to create host view %@", self.bundleIdentifier);
        completion(nil, error);
        return;
    }

    hostedView.userInteractionEnabled = YES;
    completion(hostedView, nil);
}

- (void)pollSceneForBundleIdentifier:(NSString *)bundleIdentifier
                          generation:(NSUInteger)generation
                             attempt:(NSUInteger)attempt
                          completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    id scene = [self sceneForBundleIdentifier:bundleIdentifier];
    if (scene) {
        SWFileLog(@"SCENE-3 found %@ attempts=%lu", bundleIdentifier, (unsigned long)attempt);
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    if (attempt == 0 || attempt == 10 || attempt == 20 || attempt == 30) {
        id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
        id appScene = SWMsg0(application, NSSelectorFromString(@"mainScene"));
        id manager = [self sceneManager];
        id managerScenes = nil;
        @try { managerScenes = [manager valueForKey:@"_scenesByID"]; }
        @catch (__unused NSException *exception) {}
        if (!managerScenes) managerScenes = SWMsg0(manager, NSSelectorFromString(@"scenes"));
        NSUInteger count = [managerScenes respondsToSelector:@selector(count)] ? (NSUInteger)[managerScenes count] : 0;
        SWFileLog(@"SCENE-DIAG %@ attempt=%lu app=%@ mainScene=%@ manager=%@ collection=%@ count=%lu",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  application,
                  appScene,
                  manager,
                  [managerScenes class],
                  (unsigned long)count);
    }

    if (attempt >= 40) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for FBScene."}];
        SWFileLog(@"SCENE-3 timeout %@", bundleIdentifier);
        completion(nil, error);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollSceneForBundleIdentifier:bundleIdentifier generation:generation attempt:attempt + 1 completion:completion];
    });
}

- (void)openBundleIdentifier:(NSString *)bundleIdentifier completion:(SWSceneHostCompletion)completion {
    if (bundleIdentifier.length == 0) {
        completion(nil, [NSError errorWithDomain:@"com.dream.splitwindow" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Empty bundle identifier."}]);
        return;
    }

    [self close];
    self.openGeneration += 1;
    NSUInteger generation = self.openGeneration;
    self.bundleIdentifier = bundleIdentifier;

    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    SWFileLog(@"SCENE-0 app lookup %@ app=%@ mainScene=%@",
              bundleIdentifier,
              application,
              SWMsg0(application, NSSelectorFromString(@"mainScene")));

    id existingScene = [self sceneForBundleIdentifier:bundleIdentifier];
    if (existingScene) {
        [self finishOpenForScene:existingScene generation:generation completion:completion];
        return;
    }

    [self launchSuspended:bundleIdentifier];
    [self pollSceneForBundleIdentifier:bundleIdentifier generation:generation attempt:0 completion:completion];
}

- (void)close {
    self.openGeneration += 1;

    if (self.presenter) {
        SWVoid0(self.presenter, NSSelectorFromString(@"deactivate"));
        SWVoid0(self.presenter, NSSelectorFromString(@"invalidate"));
    }

    [self.fallbackHostView removeFromSuperview];
    if (self.scene) [self setScene:self.scene foreground:NO];

    if (self.bundleIdentifier) SWFileLog(@"HOST closed %@", self.bundleIdentifier);
    self.presenter = nil;
    self.fallbackHostView = nil;
    self.scene = nil;
    self.bundleIdentifier = nil;
}

@end
