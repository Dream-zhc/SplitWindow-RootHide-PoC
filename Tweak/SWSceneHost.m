#import "SWSceneHost.h"
#import "SWLogger.h"
#import <dlfcn.h>
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

static void SWVoidInteger(id obj, SEL sel, NSInteger value) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(obj, sel, value);
}

static void SWVoidCGRect(id obj, SEL sel, CGRect value) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(obj, sel, value);
}

static int SWInt0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return 0;
    return ((int (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL SWBool0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    NSMethodSignature *signature = [obj methodSignatureForSelector:sel];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnLength != sizeof(BOOL)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSUInteger SWUInteger0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return 0;
    NSMethodSignature *signature = [obj methodSignatureForSelector:sel];
    if (!signature || signature.numberOfArguments != 2 ||
        signature.methodReturnLength != sizeof(NSUInteger)) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSString *SWGlobalStringConstant(const char *symbolName) {
    if (!symbolName) return nil;
    void *symbol = dlsym(RTLD_DEFAULT, symbolName);
    if (!symbol) return nil;
    __unsafe_unretained id *slot = (__unsafe_unretained id *)symbol;
    id value = slot ? *slot : nil;
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

typedef NS_ENUM(NSInteger, SWSceneHostState) {
    SWSceneHostStateIdle = 0,
    SWSceneHostStateLaunching,
    SWSceneHostStateWindowed,
    SWSceneHostStateBackgrounded,
};

@interface SWSceneHost ()
@property (nonatomic, copy, readwrite, nullable) NSString *bundleIdentifier;
@property (nonatomic, strong, readwrite, nullable) id scene;
@property (nonatomic, strong, readwrite, nullable) id presenter;
@property (nonatomic, strong, nullable) UIView *fallbackHostView;
@property (nonatomic, copy, nullable) NSString *sceneIdentifier;
@property (nonatomic) BOOL presentationSuspended;
@property (nonatomic) CFAbsoluteTime openStartedAt;
@property (nonatomic) NSUInteger openGeneration;
@property (nonatomic) SWSceneHostState state;
@end

@implementation SWSceneHost

- (id)sceneManager {
    Class managerClass = NSClassFromString(@"FBSceneManager");
    return SWMsg0(managerClass, NSSelectorFromString(@"sharedInstance"));
}

- (id)processManager {
    return SWMsg0(NSClassFromString(@"FBProcessManager"), NSSelectorFromString(@"sharedInstance"));
}

- (id)processIdentityForBundleIdentifier:(NSString *)bundleIdentifier {
    return SWMsg1(NSClassFromString(@"RBSProcessIdentity"),
                  NSSelectorFromString(@"identityForEmbeddedApplicationIdentifier:"),
                  bundleIdentifier);
}

- (id)processHandleForBundleIdentifier:(NSString *)bundleIdentifier {
    id identity = [self processIdentityForBundleIdentifier:bundleIdentifier];
    if (!identity) return nil;
    id predicate = SWMsg1(NSClassFromString(@"RBSProcessPredicate"),
                          NSSelectorFromString(@"predicateMatchingIdentity:"),
                          identity);
    if (!predicate) return nil;

    Class handleClass = NSClassFromString(@"RBSProcessHandle");
    SEL selector = NSSelectorFromString(@"handleForPredicate:error:");
    if (!handleClass || ![handleClass respondsToSelector:selector]) return nil;

    NSError *error = nil;
    id handle = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(handleClass,
                                                                 selector,
                                                                 predicate,
                                                                 &error);
    if (!handle && error) SWFileLog(@"PROC handle lookup %@ error=%@", bundleIdentifier, error);
    return handle;
}

- (id)springBoardApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    id controller = SWMsg0(NSClassFromString(@"SBApplicationController"), NSSelectorFromString(@"sharedInstance"));
    if (!controller) return nil;
    id app = SWMsg1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    if (!app) app = SWMsg1(controller, NSSelectorFromString(@"applicationWithDisplayIdentifier:"), bundleIdentifier);
    return app;
}

- (NSString *)frontMostBundleIdentifier {
    UIApplication *springBoard = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if (![springBoard respondsToSelector:selector]) return nil;
    id app = ((id (*)(id, SEL))objc_msgSend)(springBoard, selector);
    for (NSString *name in @[@"bundleIdentifier", @"displayIdentifier"]) {
        id value = SWMsg0(app, NSSelectorFromString(name));
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

- (BOOL)isBundleIdentifierForeground:(NSString *)bundleIdentifier {
    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    if (!application) return NO;

    for (NSString *selectorName in @[@"isForeground", @"isFrontmost", @"isRunningForeground"]) {
        if (SWBool0(application, NSSelectorFromString(selectorName))) return YES;
    }

    id processState = SWMsg0(application, NSSelectorFromString(@"processState"));
    for (NSString *selectorName in @[@"isForeground", @"isFrontmost"]) {
        if (SWBool0(processState, NSSelectorFromString(selectorName))) return YES;
    }

    NSString *description = [[processState description] lowercaseString];
    return [description containsString:@"visibility: foreground"] ||
           [description containsString:@"visibility=foreground"] ||
           [description containsString:@"foregroundrunning"];
}

- (BOOL)isSceneUsable:(id)scene {
    if (!scene) return NO;
    SEL validSelector = NSSelectorFromString(@"isValid");
    if ([scene respondsToSelector:validSelector]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(scene, validSelector);
    }
    return YES;
}

- (NSString *)canonicalSceneIdentifierForBundleIdentifier:(NSString *)bundleIdentifier {
    id manager = [self sceneManager];
    id generated = SWMsg1(manager,
                          NSSelectorFromString(@"_createSceneIdentifierForApplicationID:"),
                          bundleIdentifier);
    if ([generated isKindOfClass:[NSString class]] && [generated length] > 0) return generated;
    return [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier];
}

- (BOOL)scene:(id)scene matchesBundleIdentifier:(NSString *)bundleIdentifier {
    if (![self isSceneUsable:scene] || bundleIdentifier.length == 0) return NO;
    for (NSString *selectorName in @[@"identifier", @"sceneIdentifier", @"persistenceIdentifier"]) {
        id value = SWMsg0(scene, NSSelectorFromString(selectorName));
        if ([[value description] containsString:bundleIdentifier]) return YES;
    }
    id identity = SWMsg0(scene, NSSelectorFromString(@"identity"));
    for (NSString *selectorName in @[@"identifier", @"stringRepresentation"]) {
        id value = SWMsg0(identity, NSSelectorFromString(selectorName));
        if ([[value description] containsString:bundleIdentifier]) return YES;
    }
    return [[scene description] containsString:bundleIdentifier];
}

- (id)sceneFromCollection:(id)collection bundleIdentifier:(NSString *)bundleIdentifier {
    if ([collection isKindOfClass:[NSDictionary class]]) {
        for (id key in [collection allKeys]) {
            id scene = [collection objectForKey:key];
            if ([self scene:scene matchesBundleIdentifier:bundleIdentifier]) return scene;
        }
        return nil;
    }
    if ([collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id scene in collection) {
            if ([self scene:scene matchesBundleIdentifier:bundleIdentifier]) return scene;
        }
    }
    return nil;
}

- (id)systemDefaultSceneForBundleIdentifier:(NSString *)bundleIdentifier matchedIdentifier:(NSString **)matchedIdentifier {
    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    for (NSString *selectorName in @[@"mainScene", @"_mainScene", @"primaryScene", @"scene"]) {
        id applicationScene = SWMsg0(application, NSSelectorFromString(selectorName));
        if ([self scene:applicationScene matchesBundleIdentifier:bundleIdentifier]) {
            NSString *identifier = [SWMsg0(applicationScene, NSSelectorFromString(@"identifier")) description];
            if (matchedIdentifier) *matchedIdentifier = identifier;
            return applicationScene;
        }
    }

    id manager = [self sceneManager];
    if (!manager) return nil;
    NSString *canonical = [self canonicalSceneIdentifierForBundleIdentifier:bundleIdentifier];
    NSArray<NSString *> *identifiers = @[
        canonical,
        [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier],
        [NSString stringWithFormat:@"%@-default", bundleIdentifier]
    ];
    for (NSString *identifier in identifiers) {
        id scene = SWMsg1(manager, NSSelectorFromString(@"sceneWithIdentifier:"), identifier);
        if ([self isSceneUsable:scene]) {
            if (matchedIdentifier) *matchedIdentifier = identifier;
            return scene;
        }
    }

    // Some large legacy/lifecycle-heavy apps do not expose their active Scene
    // through SBApplication.mainScene even while SpringBoard is displaying it.
    // Prefer explicit collection selectors if this iOS build provides them.
    for (NSString *selectorName in @[@"scenes", @"allScenes"]) {
        id scene = [self sceneFromCollection:SWMsg0(manager, NSSelectorFromString(selectorName))
                           bundleIdentifier:bundleIdentifier];
        if (scene) {
            NSString *identifier = [SWMsg0(scene, NSSelectorFromString(@"identifier")) description];
            if (matchedIdentifier) *matchedIdentifier = identifier;
            SWFileLog(@"SCENE-SYSTEM discovered %@ via=%@ id=%@", bundleIdentifier, selectorName, identifier);
            return scene;
        }
    }

    // Last-resort read-only compatibility probe. This never creates, mutates,
    // or destroys a Scene. KVC is wrapped in @try so an iOS build that hides
    // the storage simply falls through rather than taking SpringBoard down.
    @try {
        id scenesByID = [manager valueForKey:@"_scenesByID"];
        id scene = [self sceneFromCollection:scenesByID bundleIdentifier:bundleIdentifier];
        if (scene) {
            NSString *identifier = [SWMsg0(scene, NSSelectorFromString(@"identifier")) description];
            if (matchedIdentifier) *matchedIdentifier = identifier;
            SWFileLog(@"SCENE-SYSTEM discovered %@ via=readonly-kvc id=%@", bundleIdentifier, identifier);
            return scene;
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

- (BOOL)requestSystemOpenForBundleIdentifier:(NSString *)bundleIdentifier
                           activateSuspended:(BOOL)activateSuspended {
    if (bundleIdentifier.length == 0) return NO;

    NSMutableDictionary *optionDictionary = [@{
        @"__ActivateSuspended": @(activateSuspended),
        @"__Actions": @[],
        @"__PromptUnlockDevice": @YES,
        @"__LaunchOrigin": @"__SBLaunchOriginSplitWindow",
    } mutableCopy];

    // LLDB/debugserver includes the LaunchServices generation metadata in its
    // FBS launch request. Supplying it when the private constants are exported
    // helps FrontBoard associate a cold request with the current installed app
    // registration instead of a stale LS generation. All lookups are dynamic;
    // a build that hides any of these symbols simply skips the optimization.
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    id proxy = SWMsg1(proxyClass, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleIdentifier);
    NSUInteger sequenceNumber = SWUInteger0(proxy, NSSelectorFromString(@"sequenceNumber"));
    id cacheGUID = SWMsg0(proxy, NSSelectorFromString(@"cacheGUID"));
    NSString *cacheGUIDString = SWMsg0(cacheGUID, NSSelectorFromString(@"UUIDString"));
    NSString *sequenceKey = SWGlobalStringConstant("FBSOpenApplicationOptionKeyLSSequenceNumber");
    NSString *cacheGUIDKey = SWGlobalStringConstant("FBSOpenApplicationOptionKeyLSCacheGUID");
    if (sequenceNumber > 0 && sequenceKey.length > 0) {
        optionDictionary[sequenceKey] = @(sequenceNumber);
    }
    if (cacheGUIDString.length > 0 && cacheGUIDKey.length > 0) {
        optionDictionary[cacheGUIDKey] = cacheGUIDString;
    }
    if (sequenceNumber > 0 || cacheGUIDString.length > 0) {
        SWFileLog(@"SYSTEM-OPEN LS metadata %@ sequence=%lu guid=%d",
                  bundleIdentifier,
                  (unsigned long)sequenceNumber,
                  cacheGUIDString.length > 0);
    }
    id options = SWMsg1(NSClassFromString(@"FBSOpenApplicationOptions"),
                        NSSelectorFromString(@"optionsWithDictionary:"),
                        optionDictionary);
    if (!options) {
        SWFileLog(@"SYSTEM-OPEN options unavailable %@", bundleIdentifier);
        return NO;
    }

    // Prefer the same service-level route used by SpringBoard shortcuts and
    // debugger suspended activation. It gives FrontBoard ownership of the app
    // launch transaction from the beginning instead of manually constructing
    // a Scene or routing through a higher-level workspace shim first.
    void (^completion)(void) = ^{};
    Class openServiceClass = NSClassFromString(@"FBSOpenApplicationService");
    id openService = openServiceClass ? [openServiceClass new] : nil;
    SEL openSelector = NSSelectorFromString(@"openApplication:withOptions:completion:");
    NSMethodSignature *openSignature = [openService methodSignatureForSelector:openSelector];
    if (openService && [openService respondsToSelector:openSelector] &&
        openSignature && openSignature.numberOfArguments == 5) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(openService,
                                                       openSelector,
                                                       bundleIdentifier,
                                                       options,
                                                       completion);
        SWFileLog(@"SYSTEM-OPEN request %@ suspended=%d route=fbs-service",
                  bundleIdentifier,
                  activateSuspended);
        return YES;
    }

    Class requestClass = NSClassFromString(@"FBSystemServiceOpenApplicationRequest");
    id request = SWMsg0(requestClass, NSSelectorFromString(@"request"));
    if (!request && requestClass) request = [requestClass new];
    id workspace = SWMsg0(NSClassFromString(@"SBMainWorkspace"), NSSelectorFromString(@"sharedInstance"));
    id systemService = SWMsg0(NSClassFromString(@"FBSystemService"), NSSelectorFromString(@"sharedInstance"));
    if (!systemService) systemService = SWMsg0(NSClassFromString(@"FBSystemService"), NSSelectorFromString(@"sharedService"));

    SEL workspaceSelector = NSSelectorFromString(@"systemService:handleOpenApplicationRequest:withCompletion:");
    NSMethodSignature *workspaceSignature = [workspace methodSignatureForSelector:workspaceSelector];
    if (request && workspace && systemService &&
        [workspace respondsToSelector:workspaceSelector] &&
        workspaceSignature && workspaceSignature.numberOfArguments == 5) {
        SWVoid1(request, NSSelectorFromString(@"setOptions:"), options);
        SWVoid1(request, NSSelectorFromString(@"setBundleIdentifier:"), bundleIdentifier);
        SWVoidBool(request, NSSelectorFromString(@"setTrusted:"), YES);
        id systemProcess = SWMsg0([self processManager], NSSelectorFromString(@"systemApplicationProcess"));
        if (systemProcess) SWVoid1(request, NSSelectorFromString(@"setClientProcess:"), systemProcess);
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(workspace,
                                                       workspaceSelector,
                                                       systemService,
                                                       request,
                                                       completion);
        SWFileLog(@"SYSTEM-OPEN request %@ suspended=%d route=workspace",
                  bundleIdentifier,
                  activateSuspended);
        return YES;
    }

    // Compatibility fallback only. Unlike the old `suspended:YES` process-only
    // launch, this asks SpringBoard to run the app so its own default Scene can
    // be registered. SplitWindow still never creates an FBScene itself.
    UIApplication *springBoard = UIApplication.sharedApplication;
    SEL launchSelector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *launchSignature = [springBoard methodSignatureForSelector:launchSelector];
    if ([springBoard respondsToSelector:launchSelector] && launchSignature &&
        launchSignature.numberOfArguments == 4) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard,
                                                    launchSelector,
                                                    bundleIdentifier,
                                                    NO);
        SWFileLog(@"SYSTEM-OPEN request %@ suspended=0 route=UIApplication-fallback", bundleIdentifier);
        return YES;
    }

    SWFileLog(@"SYSTEM-OPEN unavailable %@", bundleIdentifier);
    return NO;
}

- (BOOL)sendHomeButtonIfPossible {
    id controller = SWMsg0(NSClassFromString(@"SBUIController"), NSSelectorFromString(@"sharedInstance"));
    for (NSString *name in @[@"handleHomeButtonSinglePressUp", @"clickedMenuButton"]) {
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
        if ([controller respondsToSelector:selector] && signature.numberOfArguments == 2) {
            SWVoid0(controller, selector);
            SWFileLog(@"HANDOFF home selector=%@", name);
            return YES;
        }
    }
    id springBoard = UIApplication.sharedApplication;
    SEL simulatedHome = NSSelectorFromString(@"_simulateHomeButtonPress");
    NSMethodSignature *simulatedSignature = [springBoard methodSignatureForSelector:simulatedHome];
    if ([springBoard respondsToSelector:simulatedHome] && simulatedSignature.numberOfArguments == 2) {
        SWVoid0(springBoard, simulatedHome);
        SWFileLog(@"HANDOFF home selector=_simulateHomeButtonPress");
        return YES;
    }
    SWFileLog(@"HANDOFF home selector unavailable");
    return NO;
}

- (void)updateScene:(id)scene windowedForeground:(BOOL)foreground {
    if (!scene) return;
    void (^updateBlock)(id) = ^(id settings) {
        SWVoidBool(settings, NSSelectorFromString(@"setForeground:"), foreground);
        SWVoidBool(settings, NSSelectorFromString(@"setBackgrounded:"), !foreground);
        SWVoidBool(settings, NSSelectorFromString(@"setStatusBarDisabled:"), foreground);
    };

    SEL updateWithBlock = NSSelectorFromString(@"updateSettingsWithBlock:");
    if ([scene respondsToSelector:updateWithBlock]) {
        SWVoid1(scene, updateWithBlock, updateBlock);
        return;
    }

    id settings = SWMsg0(scene, NSSelectorFromString(@"mutableSettings"));
    if (!settings) {
        @try { settings = [[scene valueForKey:@"settings"] mutableCopy]; }
        @catch (__unused NSException *exception) {}
    }
    if (!settings) return;
    updateBlock(settings);
    SEL update3 = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    if ([scene respondsToSelector:update3]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, update3, settings, nil, nil);
    } else {
        SWVoid2(scene, NSSelectorFromString(@"updateSettings:withTransitionContext:"), settings, nil);
    }
}

- (UIView *)presentationViewForScene:(id)scene {
    id manager = SWMsg0(scene, NSSelectorFromString(@"uiPresentationManager"));
    if (manager) {
        NSString *identifier = [NSString stringWithFormat:@"com.dream.splitwindow.presenter.%@.%@",
                                self.bundleIdentifier ?: @"app",
                                NSUUID.UUID.UUIDString];
        id presenter = SWMsg1(manager, NSSelectorFromString(@"createPresenterWithIdentifier:"), identifier);
        if (presenter) {
            SEL modifyContext = NSSelectorFromString(@"modifyPresentationContext:");
            if ([presenter respondsToSelector:modifyContext]) {
                void (^contextBlock)(id) = ^(id context) {
                    SWVoidInteger(context, NSSelectorFromString(@"setAppearanceStyle:"), 2);
                };
                SWVoid1(presenter, modifyContext, contextBlock);
            }
            SWVoid0(presenter, NSSelectorFromString(@"activate"));
            UIView *view = SWMsg0(presenter, NSSelectorFromString(@"presentationView"));
            if ([view isKindOfClass:[UIView class]]) {
                self.presenter = presenter;
                self.presentationSuspended = NO;
                SWFileLog(@"HOST presenter active %@ sceneID=%@", self.bundleIdentifier, self.sceneIdentifier);
                return view;
            }
            SWVoid0(presenter, NSSelectorFromString(@"deactivate"));
            SWVoid0(presenter, NSSelectorFromString(@"invalidate"));
        }
    }

    Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    if (!hostClass) return nil;
    id host = nil;
    SEL describedInit = NSSelectorFromString(@"initWithScene:debugDescription:");
    if ([hostClass instancesRespondToSelector:describedInit]) {
        host = ((id (*)(id, SEL, id, id))objc_msgSend)([hostClass alloc], describedInit, scene, @"SplitWindow-default-scene");
    } else {
        SEL initSelector = NSSelectorFromString(@"initWithScene:");
        if ([hostClass instancesRespondToSelector:initSelector]) {
            host = ((id (*)(id, SEL, id))objc_msgSend)([hostClass alloc], initSelector, scene);
        }
    }
    if (![host isKindOfClass:[UIView class]]) return nil;
    self.fallbackHostView = host;
    SWFileLog(@"HOST legacy layer active %@", self.bundleIdentifier);
    return host;
}

- (void)updateSceneForHostBounds:(CGRect)hostBounds interfaceOrientation:(UIInterfaceOrientation)orientation {
    id scene = self.scene;
    if (!scene || CGRectIsEmpty(hostBounds)) return;
    CGRect sceneFrame = hostBounds;
    sceneFrame.origin = CGPointZero;

    void (^updateBlock)(id) = ^(id settings) {
        SWVoidBool(settings, NSSelectorFromString(@"setForeground:"), YES);
        SWVoidBool(settings, NSSelectorFromString(@"setBackgrounded:"), NO);
        SWVoidBool(settings, NSSelectorFromString(@"setStatusBarDisabled:"), YES);
        SWVoidCGRect(settings, NSSelectorFromString(@"setFrame:"), sceneFrame);
        SWVoidInteger(settings, NSSelectorFromString(@"setInterfaceOrientation:"), orientation);
        SWVoidInteger(settings, NSSelectorFromString(@"setDeviceOrientation:"), UIDevice.currentDevice.orientation);
    };

    SEL updateWithBlock = NSSelectorFromString(@"updateSettingsWithBlock:");
    if ([scene respondsToSelector:updateWithBlock]) {
        SWVoid1(scene, updateWithBlock, updateBlock);
    } else {
        id settings = SWMsg0(scene, NSSelectorFromString(@"mutableSettings"));
        if (!settings) {
            @try { settings = [[scene valueForKey:@"settings"] mutableCopy]; }
            @catch (__unused NSException *exception) {}
        }
        if (settings) {
            updateBlock(settings);
            SEL update3 = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
            if ([scene respondsToSelector:update3]) {
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, update3, settings, nil, nil);
            } else {
                SWVoid2(scene, NSSelectorFromString(@"updateSettings:withTransitionContext:"), settings, nil);
            }
        }
    }
    SWFileLog(@"SCENE-GEOMETRY %@ orientation=%ld frame=%@",
              self.bundleIdentifier,
              (long)orientation,
              NSStringFromCGRect(sceneFrame));
}

- (void)finishOpenForScene:(id)scene generation:(NSUInteger)generation completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration || ![self isSceneUsable:scene]) return;
    self.scene = scene;
    if (self.sceneIdentifier.length == 0) self.sceneIdentifier = [SWMsg0(scene, NSSelectorFromString(@"identifier")) description];

    CFAbsoluteTime sceneElapsed = (CFAbsoluteTimeGetCurrent() - self.openStartedAt) * 1000.0;
    SWFileLog(@"PERF scene-ready %@ %.0fms id=%@", self.bundleIdentifier, sceneElapsed, self.sceneIdentifier);

    // Bind the remote presentation while the system Scene is still suspended
    // or backgrounded whenever possible. The overlay inserts this view into its
    // final hierarchy first, then `updateSceneForHostBounds:` foregrounds the
    // Scene. That ordering preserves the app's native launch/snapshot surface
    // instead of resuming the client to its first frame before we can see it.
    UIView *hostedView = [self presentationViewForScene:scene];
    BOOL boundBeforeForeground = hostedView != nil;
    if (!hostedView) {
        // Compatibility fallback for builds where the presentation manager only
        // produces a view for a foreground Scene. Never create another Scene.
        [self updateScene:scene windowedForeground:YES];
        hostedView = [self presentationViewForScene:scene];
    }
    if (!hostedView) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow" code:3 userInfo:@{NSLocalizedDescriptionKey:@"No supported default-Scene presentation API was available."}];
        self.state = SWSceneHostStateBackgrounded;
        completion(nil, error);
        return;
    }

    self.state = SWSceneHostStateWindowed;
    hostedView.userInteractionEnabled = YES;
    CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.openStartedAt) * 1000.0;
    SWFileLog(@"PERF presentation-ready %@ %.0fms preForeground=%d",
              self.bundleIdentifier,
              elapsed,
              boundBeforeForeground);
    completion(hostedView, nil);
}

- (void)openExistingDefaultScene:(id)scene
                      generation:(NSUInteger)generation
               foregroundHandoff:(BOOL)foregroundHandoff
                      completion:(SWSceneHostCompletion)completion {
    if (!foregroundHandoff) {
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    BOOL sentHome = [self sendHomeButtonIfPossible];
    SWFileLog(@"HANDOFF foreground-self %@ homeRequested=%d", self.bundleIdentifier, sentHome);
    [self waitForForegroundReleaseOfBundleIdentifier:self.bundleIdentifier
                                               scene:scene
                                          generation:generation
                                             attempt:0
                                          completion:completion];
}

- (void)waitForForegroundReleaseOfBundleIdentifier:(NSString *)bundleIdentifier
                                              scene:(id)scene
                                         generation:(NSUInteger)generation
                                            attempt:(NSUInteger)attempt
                                         completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;
    NSString *frontMost = [self frontMostBundleIdentifier];
    BOOL frontClaimsTarget = [frontMost isEqualToString:bundleIdentifier];
    BOOL processClaimsTarget = [self isBundleIdentifierForeground:bundleIdentifier];

    if (!frontClaimsTarget && !processClaimsTarget) {
        SWFileLog(@"HANDOFF foreground released %@ attempts=%lu front=%@",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  frontMost);
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    // SBApplicationProcessState visibility frequently remains Foreground for a
    // few hundred milliseconds after Home has already removed the fullscreen
    // display. Treat that as stale once the front-display source no longer
    // names the target and the transition has had ~300ms to settle. The v0.6.1
    // logic waited on stale process visibility and timed out even though Home
    // was already visible.
    if (!frontClaimsTarget && attempt >= 18) {
        SWFileLog(@"HANDOFF foreground released-stale-process %@ attempts=%lu processForeground=%d",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  processClaimsTarget);
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    // This polling exists only for the foreground-self handoff and normally
    // lasts one or two display frames. It prevents presenting one Scene in the
    // system fullscreen host and SplitWindow at the same time (black surface).
    if (attempt >= 75) {
        SWFileLog(@"HANDOFF foreground release timeout %@ front=%@", bundleIdentifier, frontMost);
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:31
                                         userInfo:@{NSLocalizedDescriptionKey:@"Could not release the app's fullscreen presentation safely."}];
        self.state = SWSceneHostStateBackgrounded;
        completion(nil, error);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitForForegroundReleaseOfBundleIdentifier:bundleIdentifier
                                                    scene:scene
                                               generation:generation
                                                  attempt:attempt + 1
                                               completion:completion];
    });
}

- (void)pollSystemDefaultSceneForBundleIdentifier:(NSString *)bundleIdentifier
                                        generation:(NSUInteger)generation
                                           attempt:(NSUInteger)attempt
                                         escalated:(BOOL)escalated
                                 foregroundHandoff:(BOOL)foregroundHandoff
                                        completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    NSString *matchedIdentifier = nil;
    id scene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if ([self isSceneUsable:scene]) {
        self.sceneIdentifier = matchedIdentifier;
        self.scene = scene;
        BOOL mustReleaseSystemFullscreen = foregroundHandoff || escalated;
        SWFileLog(@"SCENE-SYSTEM acquired %@ attempt=%lu id=%@ route=%@ release=%d",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  matchedIdentifier,
                  escalated ? @"foreground-fallback" : @"suspended-system",
                  mustReleaseSystemFullscreen);
        [self openExistingDefaultScene:scene
                            generation:generation
                     foregroundHandoff:mustReleaseSystemFullscreen
                            completion:completion];
        return;
    }

    // A suspended trusted SystemService request is the preferred path because
    // it asks SpringBoard to construct the real installed app default Scene
    // without SplitWindow inventing a second scene. If a particular iOS build
    // does not materialize a Scene for suspended activation, escalate once to
    // a normal system open request and immediately hand that same Scene back
    // from fullscreen before presenting it in the mini-window.
    if (!escalated && attempt == 48) {
        BOOL requested = [self requestSystemOpenForBundleIdentifier:bundleIdentifier activateSuspended:NO];
        if (!requested) {
            NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                 code:25
                                             userInfo:@{NSLocalizedDescriptionKey:@"SpringBoard could not create the app's system default Scene."}];
            self.state = SWSceneHostStateIdle;
            completion(nil, error);
            return;
        }
        SWFileLog(@"SYSTEM-OPEN escalate foreground %@ after=%lums",
                  bundleIdentifier,
                  (unsigned long)(attempt * 16));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self pollSystemDefaultSceneForBundleIdentifier:bundleIdentifier
                                                  generation:generation
                                                     attempt:attempt + 1
                                                   escalated:YES
                                           foregroundHandoff:foregroundHandoff
                                                  completion:completion];
        });
        return;
    }

    if (attempt >= 120) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey:@"Timed out waiting for SpringBoard's system default Scene."}];
        self.state = SWSceneHostStateIdle;
        SWFileLog(@"SCENE-SYSTEM timeout %@ escalated=%d", bundleIdentifier, escalated);
        completion(nil, error);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollSystemDefaultSceneForBundleIdentifier:bundleIdentifier
                                              generation:generation
                                                 attempt:attempt + 1
                                               escalated:escalated
                                       foregroundHandoff:foregroundHandoff
                                              completion:completion];
    });
}

- (void)openBundleIdentifier:(NSString *)bundleIdentifier
           foregroundHandoff:(BOOL)foregroundHandoff
                  completion:(SWSceneHostCompletion)completion {
    if (bundleIdentifier.length == 0) {
        completion(nil, [NSError errorWithDomain:@"com.dream.splitwindow" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Empty bundle identifier."}]);
        return;
    }

    self.openStartedAt = CFAbsoluteTimeGetCurrent();
    self.openGeneration += 1;
    NSUInteger generation = self.openGeneration;

    if (self.bundleIdentifier.length > 0 && ![self.bundleIdentifier isEqualToString:bundleIdentifier]) {
        [self dismissPresentationPreservingScene];
        self.scene = nil;
        self.sceneIdentifier = nil;
        self.bundleIdentifier = nil;
        // `dismissPresentationPreservingScene` intentionally invalidates the
        // previous async generation, so reserve a fresh generation for this app.
        self.openGeneration += 1;
        generation = self.openGeneration;
    }

    self.bundleIdentifier = bundleIdentifier;
    self.state = SWSceneHostStateLaunching;
    BOOL targetIsSystemForeground = foregroundHandoff || [self isBundleIdentifierForeground:bundleIdentifier];
    SWFileLog(@"STATE launching %@ foregroundHandoff=%d detectedForeground=%d",
              bundleIdentifier,
              foregroundHandoff,
              targetIsSystemForeground);

    NSString *matchedIdentifier = nil;
    id existingScene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if ([self isSceneUsable:existingScene]) {
        self.sceneIdentifier = matchedIdentifier;
        self.scene = existingScene;
        SWFileLog(@"SCENE-SYSTEM reuse %@ id=%@", bundleIdentifier, matchedIdentifier);
        [self openExistingDefaultScene:existingScene
                            generation:generation
                     foregroundHandoff:targetIsSystemForeground
                            completion:completion];
        return;
    }

    id handle = [self processHandleForBundleIdentifier:bundleIdentifier];
    int pid = SWInt0(handle, NSSelectorFromString(@"pid"));
    SWFileLog(@"PROC system-scene request %@ state=%@ pid=%d",
              bundleIdentifier,
              pid > 0 ? @"warm-no-scene" : @"cold",
              pid);

    if (![self requestSystemOpenForBundleIdentifier:bundleIdentifier activateSuspended:YES]) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:26
                                         userInfo:@{NSLocalizedDescriptionKey:@"No safe SpringBoard system-open API was available."}];
        self.state = SWSceneHostStateIdle;
        completion(nil, error);
        return;
    }
    [self pollSystemDefaultSceneForBundleIdentifier:bundleIdentifier
                                          generation:generation
                                             attempt:0
                                           escalated:NO
                                   foregroundHandoff:targetIsSystemForeground
                                          completion:completion];
}

- (void)invalidatePresenter {
    if (self.presenter) {
        SWVoid0(self.presenter, NSSelectorFromString(@"deactivate"));
        SWVoid0(self.presenter, NSSelectorFromString(@"invalidate"));
    }
    self.presenter = nil;
    [self.fallbackHostView removeFromSuperview];
    self.fallbackHostView = nil;
}

- (void)dismissPresentationPreservingScene {
    self.openGeneration += 1;
    [self invalidatePresenter];
    if ([self isSceneUsable:self.scene]) [self updateScene:self.scene windowedForeground:NO];
    self.presentationSuspended = YES;
    self.state = self.scene ? SWSceneHostStateBackgrounded : SWSceneHostStateIdle;
    if (self.bundleIdentifier) SWFileLog(@"STATE backgrounded %@ scene=%@", self.bundleIdentifier, self.scene);
}

- (void)relinquishPresentationForSystemForeground {
    self.openGeneration += 1;
    [self invalidatePresenter];
    if ([self isSceneUsable:self.scene]) {
        void (^restoreBlock)(id) = ^(id settings) {
            SWVoidBool(settings, NSSelectorFromString(@"setStatusBarDisabled:"), NO);
        };
        SEL selector = NSSelectorFromString(@"updateSettingsWithBlock:");
        if ([self.scene respondsToSelector:selector]) SWVoid1(self.scene, selector, restoreBlock);
    }
    self.presentationSuspended = YES;
    self.state = SWSceneHostStateBackgrounded;
    SWFileLog(@"STATE relinquish-fullscreen %@ scene=%@", self.bundleIdentifier, self.scene);
}

- (void)close {
    [self dismissPresentationPreservingScene];
    self.scene = nil;
    self.sceneIdentifier = nil;
    self.bundleIdentifier = nil;
    self.state = SWSceneHostStateIdle;
}

@end
