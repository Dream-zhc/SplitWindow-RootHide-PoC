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

static id SWMsg2(id obj, SEL sel, id a, id b) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id, id))objc_msgSend)(obj, sel, a, b);
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

static void SWVoidInsets(id obj, SEL sel, UIEdgeInsets value) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, UIEdgeInsets))objc_msgSend)(obj, sel, value);
}

static int SWInt0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return 0;
    return ((int (*)(id, SEL))objc_msgSend)(obj, sel);
}

@interface SWSceneHost ()
@property (nonatomic, copy, readwrite, nullable) NSString *bundleIdentifier;
@property (nonatomic, strong, readwrite, nullable) id scene;
@property (nonatomic, strong, readwrite, nullable) id presenter;
@property (nonatomic, strong, nullable) UIView *fallbackHostView;
@property (nonatomic, copy, nullable) NSString *sceneIdentifier;
@property (nonatomic) BOOL ownsScene;
@property (nonatomic) BOOL presentationSuspended;
@property (nonatomic) CFAbsoluteTime openStartedAt;
@property (nonatomic) NSUInteger openGeneration;
@end

@implementation SWSceneHost

- (id)sceneManager {
    Class managerClass = NSClassFromString(@"FBSceneManager");
    id manager = SWMsg0(managerClass, NSSelectorFromString(@"sharedInstance"));
    return manager;
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

- (BOOL)registerProcessHandleIfPossible:(id)processHandle {
    id manager = [self processManager];
    SEL auditSelector = NSSelectorFromString(@"auditToken");
    SEL registerSelector = NSSelectorFromString(@"registerProcessForAuditToken:");
    if (!processHandle || !manager ||
        ![processHandle respondsToSelector:auditSelector] ||
        ![manager respondsToSelector:registerSelector]) {
        return NO;
    }

    NSMethodSignature *auditSignature = [processHandle methodSignatureForSelector:auditSelector];
    NSMethodSignature *registerSignature = [manager methodSignatureForSelector:registerSelector];
    if (!auditSignature || !registerSignature || auditSignature.methodReturnLength == 0 ||
        registerSignature.numberOfArguments < 3) return NO;

    NSUInteger tokenLength = auditSignature.methodReturnLength;
    NSUInteger argumentLength = 0;
    NSGetSizeAndAlignment([registerSignature getArgumentTypeAtIndex:2], &argumentLength, NULL);
    NSUInteger bufferLength = MAX(tokenLength, argumentLength);
    void *token = calloc(1, bufferLength);
    if (!token) return NO;

    BOOL success = NO;
    @try {
        NSInvocation *auditInvocation = [NSInvocation invocationWithMethodSignature:auditSignature];
        auditInvocation.target = processHandle;
        auditInvocation.selector = auditSelector;
        [auditInvocation invoke];
        [auditInvocation getReturnValue:token];

        NSInvocation *registerInvocation = [NSInvocation invocationWithMethodSignature:registerSignature];
        registerInvocation.target = manager;
        registerInvocation.selector = registerSelector;
        [registerInvocation setArgument:token atIndex:2];
        [registerInvocation invoke];
        success = YES;
    } @catch (NSException *exception) {
        SWFileLog(@"PROC register audit token exception=%@", exception);
    }
    free(token);
    return success;
}

- (id)springBoardApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    id controller = SWMsg0(controllerClass, NSSelectorFromString(@"sharedInstance"));
    if (!controller) return nil;

    id app = SWMsg1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    if (!app) app = SWMsg1(controller, NSSelectorFromString(@"applicationWithDisplayIdentifier:"), bundleIdentifier);
    return app;
}

- (BOOL)isSceneUsable:(id)scene {
    if (!scene) return NO;
    SEL validSelector = NSSelectorFromString(@"isValid");
    if ([scene respondsToSelector:validSelector]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(scene, validSelector);
    }
    return YES;
}

- (id)systemDefaultSceneForBundleIdentifier:(NSString *)bundleIdentifier matchedIdentifier:(NSString **)matchedIdentifier {
    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    id mainScene = SWMsg0(application, NSSelectorFromString(@"mainScene"));
    if ([self isSceneUsable:mainScene]) {
        if (matchedIdentifier) *matchedIdentifier = [SWMsg0(mainScene, NSSelectorFromString(@"identifier")) description];
        return mainScene;
    }

    id manager = [self sceneManager];
    if (!manager) return nil;
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    id generatedIdentifier = SWMsg1(manager,
                                    NSSelectorFromString(@"_createSceneIdentifierForApplicationID:"),
                                    bundleIdentifier);
    if ([generatedIdentifier isKindOfClass:[NSString class]] && [generatedIdentifier length] > 0) {
        [identifiers addObject:generatedIdentifier];
    }
    [identifiers addObjectsFromArray:@[
        [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier],
        [NSString stringWithFormat:@"sceneID:%@", bundleIdentifier],
        [NSString stringWithFormat:@"%@-default", bundleIdentifier]
    ]];
    for (NSString *identifier in identifiers) {
        id scene = SWMsg1(manager, NSSelectorFromString(@"sceneWithIdentifier:"), identifier);
        if ([self isSceneUsable:scene]) {
            if (matchedIdentifier) *matchedIdentifier = identifier;
            return scene;
        }
    }
    return nil;
}

- (void)launchSuspended:(NSString *)bundleIdentifier {
    UIApplication *application = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(application, selector, bundleIdentifier, YES);
        SWFileLog(@"PROC launch requested %@ suspended=1", bundleIdentifier);
        return;
    }
    SWFileLog(@"PROC launch selector unavailable %@", bundleIdentifier);
}

- (UIInterfaceOrientation)currentInterfaceOrientation {
    id springBoard = UIApplication.sharedApplication;
    SEL frontMostSelector = NSSelectorFromString(@"_frontMostAppOrientation");
    if ([springBoard respondsToSelector:frontMostSelector]) {
        NSInteger value = ((NSInteger (*)(id, SEL))objc_msgSend)(springBoard, frontMostSelector);
        if (value >= UIInterfaceOrientationPortrait && value <= UIInterfaceOrientationLandscapeRight) {
            return (UIInterfaceOrientation)value;
        }
    }
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            NSString *persistentIdentifier = windowScene.session.persistentIdentifier ?: @"";
            NSString *className = NSStringFromClass(windowScene.class);
            if (![persistentIdentifier isEqualToString:@"com.apple.springboard"] &&
                ![className isEqualToString:@"SBWindowScene"]) continue;
            if (scene.activationState == UISceneActivationStateForegroundActive ||
                scene.activationState == UISceneActivationStateForegroundInactive) {
                if (windowScene.interfaceOrientation != UIInterfaceOrientationUnknown) {
                    return windowScene.interfaceOrientation;
                }
            }
        }
    }
    return UIInterfaceOrientationPortrait;
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

- (id)createOwnedSceneForProcessHandle:(id)processHandle error:(NSError **)errorOut {
    NSString *bundleIdentifier = self.bundleIdentifier;
    id sceneManager = [self sceneManager];
    if (!sceneManager || bundleIdentifier.length == 0) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:20
                                                   userInfo:@{NSLocalizedDescriptionKey:@"FBSceneManager unavailable."}];
        return nil;
    }

    Class definitionClass = NSClassFromString(@"FBSMutableSceneDefinition");
    Class sceneIdentityClass = NSClassFromString(@"FBSSceneIdentity");
    Class clientIdentityClass = NSClassFromString(@"FBSSceneClientIdentity");
    Class specificationClass = NSClassFromString(@"UIApplicationSceneSpecification");
    Class parametersClass = NSClassFromString(@"FBSMutableSceneParameters");
    Class settingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
    Class clientSettingsClass = NSClassFromString(@"UIMutableApplicationSceneClientSettings");

    if (!definitionClass || !sceneIdentityClass || !clientIdentityClass || !specificationClass ||
        !parametersClass || !settingsClass || !clientSettingsClass) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:21
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Required FrontBoard scene classes are unavailable."}];
        return nil;
    }

    id processIdentity = SWMsg0(processHandle, NSSelectorFromString(@"identity"));
    if (!processIdentity) processIdentity = [self processIdentityForBundleIdentifier:bundleIdentifier];
    if (!processIdentity) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:22
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Could not resolve target process identity."}];
        return nil;
    }

    // Use the application's canonical/default scene identity. FrontBoardAppLauncher
    // style random secondary scene identities can render an empty surface for
    // apps which effectively support only their default scene (WeChat is one of
    // the important cases we need to handle here).
    id generatedIdentifier = SWMsg1(sceneManager,
                                    NSSelectorFromString(@"_createSceneIdentifierForApplicationID:"),
                                    bundleIdentifier);
    NSString *sceneIdentifier = ([generatedIdentifier isKindOfClass:[NSString class]] &&
                                 [generatedIdentifier length] > 0)
        ? generatedIdentifier
        : [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier];

    id racedScene = SWMsg1(sceneManager, NSSelectorFromString(@"sceneWithIdentifier:"), sceneIdentifier);
    if ([self isSceneUsable:racedScene]) {
        self.sceneIdentifier = sceneIdentifier;
        self.ownsScene = NO;
        SWFileLog(@"SCENE-DEFAULT raced %@ id=%@ scene=%@", bundleIdentifier, sceneIdentifier, racedScene);
        return racedScene;
    }
    id definition = SWMsg0(definitionClass, NSSelectorFromString(@"definition"));
    id sceneIdentity = SWMsg1(sceneIdentityClass, NSSelectorFromString(@"identityForIdentifier:"), sceneIdentifier);
    id clientIdentity = SWMsg1(clientIdentityClass,
                               NSSelectorFromString(@"identityForProcessIdentity:"),
                               processIdentity);
    id specification = SWMsg0(specificationClass, NSSelectorFromString(@"specification"));
    id parameters = SWMsg1(parametersClass,
                           NSSelectorFromString(@"parametersForSpecification:"),
                           specification);
    if (!definition || !sceneIdentity || !clientIdentity || !specification || !parameters) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:23
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Failed to build FrontBoard scene definition."}];
        return nil;
    }

    SWVoid1(definition, NSSelectorFromString(@"setIdentity:"), sceneIdentity);
    SWVoid1(definition, NSSelectorFromString(@"setClientIdentity:"), clientIdentity);
    SWVoid1(definition, NSSelectorFromString(@"setSpecification:"), specification);

    id displayConfiguration = SWMsg0(UIScreen.mainScreen, NSSelectorFromString(@"displayConfiguration"));
    NSString *persistenceIdentifier = NSUUID.UUID.UUIDString;
    void (^updateSettings)(id) = ^(id targetSettings) {
        SWVoidBool(targetSettings, NSSelectorFromString(@"setCanShowAlerts:"), YES);
        SWVoidBool(targetSettings, NSSelectorFromString(@"setForeground:"), YES);
        SWVoidInteger(targetSettings, NSSelectorFromString(@"setLevel:"), 1);
        SWVoid1(targetSettings, NSSelectorFromString(@"setPersistenceIdentifier:"), persistenceIdentifier);
        SWVoidBool(targetSettings, NSSelectorFromString(@"setStatusBarDisabled:"), YES);
        SWVoidInsets(targetSettings, NSSelectorFromString(@"setPeripheryInsets:"), UIEdgeInsetsZero);
        SWVoidInsets(targetSettings, NSSelectorFromString(@"setSafeAreaInsetsPortrait:"), UIEdgeInsetsZero);
        if (displayConfiguration) {
            SWVoid1(targetSettings, NSSelectorFromString(@"setDisplayConfiguration:"), displayConfiguration);
        }
    };

    SEL updateSettingsSelector = NSSelectorFromString(@"updateSettingsWithBlock:");
    if ([parameters respondsToSelector:updateSettingsSelector]) {
        SWVoid1(parameters, updateSettingsSelector, updateSettings);
    } else {
        id settings = [settingsClass new];
        updateSettings(settings);
        SWVoid1(parameters, NSSelectorFromString(@"setSettings:"), settings);
    }

    void (^updateClientSettings)(id) = ^(id targetClientSettings) {
        // Match the proven legacy FrontBoard hosting sequence: establish the
        // scene in portrait first, then push the real geometry/orientation once
        // the presentation view is attached. Some single-scene apps fail to
        // build content when arbitrary frame/orientation is supplied too early.
        SWVoidInteger(targetClientSettings, NSSelectorFromString(@"setInterfaceOrientation:"), UIInterfaceOrientationPortrait);
        SWVoidInteger(targetClientSettings, NSSelectorFromString(@"setStatusBarStyle:"), 0);
    };
    SEL updateClientSettingsSelector = NSSelectorFromString(@"updateClientSettingsWithBlock:");
    if ([parameters respondsToSelector:updateClientSettingsSelector]) {
        SWVoid1(parameters, updateClientSettingsSelector, updateClientSettings);
    } else {
        id clientSettings = [clientSettingsClass new];
        updateClientSettings(clientSettings);
        SWVoid1(parameters, NSSelectorFromString(@"setClientSettings:"), clientSettings);
    }

    BOOL registered = [self registerProcessHandleIfPossible:processHandle];
    SWFileLog(@"SCENE-CREATE default %@ pid=%d registered=%d id=%@",
              bundleIdentifier,
              SWInt0(processHandle, NSSelectorFromString(@"pid")),
              registered,
              sceneIdentifier);

    id scene = nil;
    @try {
        scene = SWMsg2(sceneManager,
                       NSSelectorFromString(@"createSceneWithDefinition:initialParameters:"),
                       definition,
                       parameters);
    } @catch (NSException *exception) {
        SWFileLog(@"SCENE-CREATE exception %@ exception=%@", bundleIdentifier, exception);
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:24
                                                   userInfo:@{NSLocalizedDescriptionKey:@"FrontBoard rejected the requested scene."}];
        return nil;
    }
    if (!scene) {
        id raced = SWMsg1(sceneManager, NSSelectorFromString(@"sceneWithIdentifier:"), sceneIdentifier);
        if ([self isSceneUsable:raced]) {
            self.sceneIdentifier = sceneIdentifier;
            self.ownsScene = NO;
            SWFileLog(@"SCENE-DEFAULT won-race %@ id=%@ scene=%@", bundleIdentifier, sceneIdentifier, raced);
            return raced;
        }
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow"
                                                       code:24
                                                   userInfo:@{NSLocalizedDescriptionKey:@"FrontBoard did not create the requested scene."}];
        return nil;
    }

    self.sceneIdentifier = sceneIdentifier;
    self.ownsScene = YES;
    SWFileLog(@"SCENE-CREATE default success %@ scene=%@", bundleIdentifier, scene);
    return scene;
}

- (UIView *)modernPresentationViewForScene:(id)scene {
    id manager = SWMsg0(scene, NSSelectorFromString(@"uiPresentationManager"));
    if (!manager) return nil;

    id presenter = self.presenter;
    if (!presenter) {
        NSString *identifier = [NSString stringWithFormat:@"com.dream.splitwindow.presenter.%@.%@",
                                self.bundleIdentifier ?: @"app",
                                NSUUID.UUID.UUIDString];
        presenter = SWMsg1(manager, NSSelectorFromString(@"createPresenterWithIdentifier:"), identifier);
        if (presenter) SWFileLog(@"HOST presenter created %@ id=%@", self.bundleIdentifier, identifier);
    }
    if (!presenter) return nil;

    SEL modifyContext = NSSelectorFromString(@"modifyPresentationContext:");
    if ([presenter respondsToSelector:modifyContext]) {
        void (^contextBlock)(id) = ^(id context) {
            SWVoidInteger(context, NSSelectorFromString(@"setAppearanceStyle:"), 2);
        };
        SWVoid1(presenter, modifyContext, contextBlock);
    }

    SWVoid0(presenter, NSSelectorFromString(@"activate"));
    UIView *view = SWMsg0(presenter, NSSelectorFromString(@"presentationView"));
    if (![view isKindOfClass:[UIView class]]) {
        SWVoid0(presenter, NSSelectorFromString(@"deactivate"));
        SWVoid0(presenter, NSSelectorFromString(@"invalidate"));
        return nil;
    }

    self.presenter = presenter;
    self.presentationSuspended = NO;
    SWFileLog(@"HOST presenter active %@ sceneID=%@", self.bundleIdentifier, self.sceneIdentifier);
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

- (void)updateSceneForHostBounds:(CGRect)hostBounds interfaceOrientation:(UIInterfaceOrientation)orientation {
    id scene = self.scene;
    if (!scene) return;

    CGRect sceneFrame = hostBounds;
    sceneFrame.origin = CGPointZero;
    if (UIInterfaceOrientationIsLandscape(orientation) && sceneFrame.size.width > sceneFrame.size.height) {
        CGFloat width = sceneFrame.size.width;
        sceneFrame.size.width = sceneFrame.size.height;
        sceneFrame.size.height = width;
    }

    void (^updateBlock)(id) = ^(id settings) {
        SWVoidBool(settings, NSSelectorFromString(@"setForeground:"), YES);
        SWVoidBool(settings, NSSelectorFromString(@"setBackgrounded:"), NO);
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
    if (generation != self.openGeneration) return;

    self.scene = scene;
    SWFileLog(@"SCENE-ACTIVATE %@ scene=%@ owned=%d", self.bundleIdentifier, scene, self.ownsScene);
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
    CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.openStartedAt) * 1000.0;
    SWFileLog(@"OPEN ready %@ source=%@ elapsed=%.0fms",
              self.bundleIdentifier,
              self.ownsScene ? @"owned" : @"system",
              elapsed);
    completion(hostedView, nil);
}

- (BOOL)resumeWarmSceneForBundleIdentifier:(NSString *)bundleIdentifier
                                 generation:(NSUInteger)generation
                                  completion:(SWSceneHostCompletion)completion {
    if (![self.bundleIdentifier isEqualToString:bundleIdentifier] || ![self isSceneUsable:self.scene]) return NO;

    [self setScene:self.scene foreground:YES];
    UIView *hostedView = [self modernPresentationViewForScene:self.scene];
    if (!hostedView && self.fallbackHostView) hostedView = self.fallbackHostView;
    if (!hostedView) return NO;

    self.presentationSuspended = NO;
    hostedView.userInteractionEnabled = YES;
    CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.openStartedAt) * 1000.0;
    SWFileLog(@"OPEN warm-resume %@ elapsed=%.0fms", bundleIdentifier, elapsed);
    if (generation == self.openGeneration) completion(hostedView, nil);
    return YES;
}

- (void)pollSystemSceneForBundleIdentifier:(NSString *)bundleIdentifier
                              processHandle:(id)processHandle
                                 generation:(NSUInteger)generation
                                    attempt:(NSUInteger)attempt
                                maxAttempts:(NSUInteger)maxAttempts
                                 completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    NSString *matchedIdentifier = nil;
    id systemScene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if (systemScene) {
        self.sceneIdentifier = matchedIdentifier.length > 0 ? matchedIdentifier : [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier];
        self.ownsScene = NO;
        SWFileLog(@"SCENE-SYSTEM found %@ attempt=%lu id=%@ scene=%@",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  self.sceneIdentifier,
                  systemScene);
        [self finishOpenForScene:systemScene generation:generation completion:completion];
        return;
    }

    if (attempt >= maxAttempts) {
        SWFileLog(@"SCENE-SYSTEM miss %@ after=%lums fallback=default-owned",
                  bundleIdentifier,
                  (unsigned long)(maxAttempts * 50));
        [self finishOpenForProcessHandle:processHandle generation:generation completion:completion];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollSystemSceneForBundleIdentifier:bundleIdentifier
                                   processHandle:processHandle
                                      generation:generation
                                         attempt:attempt + 1
                                     maxAttempts:maxAttempts
                                      completion:completion];
    });
}

- (void)finishOpenForProcessHandle:(id)processHandle
                        generation:(NSUInteger)generation
                         completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    NSError *sceneError = nil;
    id scene = [self createOwnedSceneForProcessHandle:processHandle error:&sceneError];
    if (!scene) {
        SWFileLog(@"SCENE-CREATE failed %@ error=%@", self.bundleIdentifier, sceneError);
        completion(nil, sceneError);
        return;
    }
    [self finishOpenForScene:scene generation:generation completion:completion];
}

- (void)pollProcessForBundleIdentifier:(NSString *)bundleIdentifier
                             generation:(NSUInteger)generation
                                attempt:(NSUInteger)attempt
                             completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    NSString *matchedIdentifier = nil;
    id earlySystemScene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if (earlySystemScene) {
        self.sceneIdentifier = matchedIdentifier.length > 0 ? matchedIdentifier : [NSString stringWithFormat:@"sceneID:%@-default", bundleIdentifier];
        self.ownsScene = NO;
        SWFileLog(@"SCENE-SYSTEM early %@ attempt=%lu id=%@",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  self.sceneIdentifier);
        [self finishOpenForScene:earlySystemScene generation:generation completion:completion];
        return;
    }

    id handle = [self processHandleForBundleIdentifier:bundleIdentifier];
    int pid = SWInt0(handle, NSSelectorFromString(@"pid"));
    if (handle && pid > 0) {
        SWFileLog(@"PROC ready %@ pid=%d attempts=%lu", bundleIdentifier, pid, (unsigned long)attempt);
        [self pollSystemSceneForBundleIdentifier:bundleIdentifier
                                   processHandle:handle
                                      generation:generation
                                         attempt:0
                                     maxAttempts:2
                                      completion:completion];
        return;
    }

    if (attempt == 0 || attempt == 10 || attempt == 20 || attempt == 30) {
        SWFileLog(@"PROC wait %@ attempt=%lu handle=%@ pid=%d",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  handle,
                  pid);
    }

    if (attempt >= 40) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey:@"Timed out waiting for the target app process."}];
        SWFileLog(@"PROC timeout %@", bundleIdentifier);
        completion(nil, error);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollProcessForBundleIdentifier:bundleIdentifier
                                  generation:generation
                                     attempt:attempt + 1
                                  completion:completion];
    });
}

- (void)openBundleIdentifier:(NSString *)bundleIdentifier completion:(SWSceneHostCompletion)completion {
    if (bundleIdentifier.length == 0) {
        completion(nil, [NSError errorWithDomain:@"com.dream.splitwindow" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Empty bundle identifier."}]);
        return;
    }

    self.openStartedAt = CFAbsoluteTimeGetCurrent();

    if ([self.bundleIdentifier isEqualToString:bundleIdentifier] && [self isSceneUsable:self.scene]) {
        self.openGeneration += 1;
        NSUInteger warmGeneration = self.openGeneration;
        if ([self resumeWarmSceneForBundleIdentifier:bundleIdentifier generation:warmGeneration completion:completion]) return;
    }

    [self close];
    self.openGeneration += 1;
    NSUInteger generation = self.openGeneration;
    self.bundleIdentifier = bundleIdentifier;

    id handle = [self processHandleForBundleIdentifier:bundleIdentifier];
    int pid = SWInt0(handle, NSSelectorFromString(@"pid"));
    SWFileLog(@"OPEN process lookup %@ handle=%@ pid=%d", bundleIdentifier, handle, pid);
    if (handle && pid > 0) {
        [self pollSystemSceneForBundleIdentifier:bundleIdentifier
                                   processHandle:handle
                                      generation:generation
                                         attempt:0
                                     maxAttempts:2
                                      completion:completion];
        return;
    }

    [self launchSuspended:bundleIdentifier];
    [self pollProcessForBundleIdentifier:bundleIdentifier generation:generation attempt:0 completion:completion];
}

- (void)dismissPresentationPreservingScene {
    if (!self.scene) return;
    if (self.presenter) SWVoid0(self.presenter, NSSelectorFromString(@"deactivate"));
    [self setScene:self.scene foreground:NO];
    self.presentationSuspended = YES;
    SWFileLog(@"HOST warm-suspend %@ scene=%@", self.bundleIdentifier, self.scene);
}

- (void)destroyOwnedSceneIfNeeded {
    if (!self.ownsScene || self.sceneIdentifier.length == 0) return;
    if (self.scene) [self setScene:self.scene foreground:NO];
    SWVoid2([self sceneManager],
            NSSelectorFromString(@"destroyScene:withTransitionContext:"),
            self.sceneIdentifier,
            nil);
    SWFileLog(@"SCENE-DESTROY %@ id=%@", self.bundleIdentifier, self.sceneIdentifier);
}

- (void)close {
    self.openGeneration += 1;

    if (self.scene) [self setScene:self.scene foreground:NO];
    if (self.presenter) {
        SWVoid0(self.presenter, NSSelectorFromString(@"deactivate"));
        SWVoid0(self.presenter, NSSelectorFromString(@"invalidate"));
    }

    [self.fallbackHostView removeFromSuperview];
    [self destroyOwnedSceneIfNeeded];

    if (self.bundleIdentifier) SWFileLog(@"HOST closed %@", self.bundleIdentifier);
    self.presenter = nil;
    self.fallbackHostView = nil;
    self.scene = nil;
    self.sceneIdentifier = nil;
    self.ownsScene = NO;
    self.presentationSuspended = NO;
    self.bundleIdentifier = nil;
}

@end
