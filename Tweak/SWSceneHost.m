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

static int SWInt0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return 0;
    return ((int (*)(id, SEL))objc_msgSend)(obj, sel);
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

- (BOOL)registerProcessHandleIfPossible:(id)processHandle {
    id manager = [self processManager];
    SEL auditSelector = NSSelectorFromString(@"auditToken");
    SEL registerSelector = NSSelectorFromString(@"registerProcessForAuditToken:");
    if (!processHandle || !manager ||
        ![processHandle respondsToSelector:auditSelector] ||
        ![manager respondsToSelector:registerSelector]) return NO;

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

- (id)systemDefaultSceneForBundleIdentifier:(NSString *)bundleIdentifier matchedIdentifier:(NSString **)matchedIdentifier {
    id application = [self springBoardApplicationForBundleIdentifier:bundleIdentifier];
    id mainScene = SWMsg0(application, NSSelectorFromString(@"mainScene"));
    if ([self isSceneUsable:mainScene]) {
        NSString *identifier = [SWMsg0(mainScene, NSSelectorFromString(@"identifier")) description];
        if (matchedIdentifier) *matchedIdentifier = identifier;
        return mainScene;
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
    return nil;
}

- (void)launchColdWindowed:(NSString *)bundleIdentifier {
    UIApplication *application = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(application, selector, bundleIdentifier, YES);
        SWFileLog(@"PROC cold-windowed launch %@ suspended=1", bundleIdentifier);
        return;
    }
    SWFileLog(@"PROC launch selector unavailable %@", bundleIdentifier);
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

- (id)createCanonicalDefaultSceneForProcessHandle:(id)processHandle error:(NSError **)errorOut {
    NSString *bundleIdentifier = self.bundleIdentifier;
    id sceneManager = [self sceneManager];
    if (!sceneManager || bundleIdentifier.length == 0) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow" code:20 userInfo:@{NSLocalizedDescriptionKey:@"FBSceneManager unavailable."}];
        return nil;
    }

    NSString *sceneIdentifier = [self canonicalSceneIdentifierForBundleIdentifier:bundleIdentifier];
    id existing = SWMsg1(sceneManager, NSSelectorFromString(@"sceneWithIdentifier:"), sceneIdentifier);
    if ([self isSceneUsable:existing]) {
        self.sceneIdentifier = sceneIdentifier;
        SWFileLog(@"SCENE-DEFAULT raced %@ id=%@", bundleIdentifier, sceneIdentifier);
        return existing;
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
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow" code:21 userInfo:@{NSLocalizedDescriptionKey:@"Required FrontBoard Scene classes are unavailable."}];
        return nil;
    }

    id processIdentity = SWMsg0(processHandle, NSSelectorFromString(@"identity"));
    if (!processIdentity) processIdentity = [self processIdentityForBundleIdentifier:bundleIdentifier];
    if (!processIdentity) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow" code:22 userInfo:@{NSLocalizedDescriptionKey:@"Could not resolve target process identity."}];
        return nil;
    }

    id definition = SWMsg0(definitionClass, NSSelectorFromString(@"definition"));
    id sceneIdentity = SWMsg1(sceneIdentityClass, NSSelectorFromString(@"identityForIdentifier:"), sceneIdentifier);
    id clientIdentity = SWMsg1(clientIdentityClass, NSSelectorFromString(@"identityForProcessIdentity:"), processIdentity);
    id specification = SWMsg0(specificationClass, NSSelectorFromString(@"specification"));
    id parameters = SWMsg1(parametersClass, NSSelectorFromString(@"parametersForSpecification:"), specification);
    if (!definition || !sceneIdentity || !clientIdentity || !specification || !parameters) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow" code:23 userInfo:@{NSLocalizedDescriptionKey:@"Failed to build canonical default Scene definition."}];
        return nil;
    }

    SWVoid1(definition, NSSelectorFromString(@"setIdentity:"), sceneIdentity);
    SWVoid1(definition, NSSelectorFromString(@"setClientIdentity:"), clientIdentity);
    SWVoid1(definition, NSSelectorFromString(@"setSpecification:"), specification);

    id displayConfiguration = SWMsg0(UIScreen.mainScreen, NSSelectorFromString(@"displayConfiguration"));
    void (^sceneSettings)(id) = ^(id settings) {
        SWVoidBool(settings, NSSelectorFromString(@"setCanShowAlerts:"), YES);
        SWVoidBool(settings, NSSelectorFromString(@"setForeground:"), YES);
        SWVoidBool(settings, NSSelectorFromString(@"setBackgrounded:"), NO);
        SWVoidInteger(settings, NSSelectorFromString(@"setLevel:"), 1);
        SWVoid1(settings, NSSelectorFromString(@"setPersistenceIdentifier:"), sceneIdentifier);
        SWVoidBool(settings, NSSelectorFromString(@"setStatusBarDisabled:"), YES);
        if (displayConfiguration) SWVoid1(settings, NSSelectorFromString(@"setDisplayConfiguration:"), displayConfiguration);
    };
    SEL updateSettings = NSSelectorFromString(@"updateSettingsWithBlock:");
    if ([parameters respondsToSelector:updateSettings]) {
        SWVoid1(parameters, updateSettings, sceneSettings);
    } else {
        id settings = [settingsClass new];
        sceneSettings(settings);
        SWVoid1(parameters, NSSelectorFromString(@"setSettings:"), settings);
    }

    void (^clientSettings)(id) = ^(id settings) {
        SWVoidInteger(settings, NSSelectorFromString(@"setInterfaceOrientation:"), UIInterfaceOrientationPortrait);
        SWVoidInteger(settings, NSSelectorFromString(@"setStatusBarStyle:"), 0);
    };
    SEL updateClientSettings = NSSelectorFromString(@"updateClientSettingsWithBlock:");
    if ([parameters respondsToSelector:updateClientSettings]) {
        SWVoid1(parameters, updateClientSettings, clientSettings);
    } else {
        id settings = [clientSettingsClass new];
        clientSettings(settings);
        SWVoid1(parameters, NSSelectorFromString(@"setClientSettings:"), settings);
    }

    BOOL registered = [self registerProcessHandleIfPossible:processHandle];
    SWFileLog(@"SCENE-CREATE canonical %@ pid=%d registered=%d id=%@",
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
        SWFileLog(@"SCENE-CREATE canonical exception %@ exception=%@", bundleIdentifier, exception);
    }
    if (!scene) scene = SWMsg1(sceneManager, NSSelectorFromString(@"sceneWithIdentifier:"), sceneIdentifier);
    if (![self isSceneUsable:scene]) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"com.dream.splitwindow" code:24 userInfo:@{NSLocalizedDescriptionKey:@"FrontBoard did not create the canonical default Scene."}];
        return nil;
    }

    self.sceneIdentifier = sceneIdentifier;
    SWFileLog(@"SCENE-CREATE canonical success %@ scene=%@", bundleIdentifier, scene);
    return scene;
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
    [self updateScene:scene windowedForeground:YES];
    UIView *hostedView = [self presentationViewForScene:scene];
    if (!hostedView) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow" code:3 userInfo:@{NSLocalizedDescriptionKey:@"No supported default-Scene presentation API was available."}];
        self.state = SWSceneHostStateBackgrounded;
        completion(nil, error);
        return;
    }

    self.state = SWSceneHostStateWindowed;
    hostedView.userInteractionEnabled = YES;
    CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.openStartedAt) * 1000.0;
    SWFileLog(@"PERF presentation-ready %@ %.0fms", self.bundleIdentifier, elapsed);
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
    if (frontMost.length == 0 || ![frontMost isEqualToString:bundleIdentifier]) {
        SWFileLog(@"HANDOFF foreground released %@ attempts=%lu front=%@",
                  bundleIdentifier,
                  (unsigned long)attempt,
                  frontMost);
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    // This polling exists only for the foreground-self handoff and normally
    // lasts one or two display frames. It prevents presenting one Scene in the
    // system fullscreen host and SplitWindow at the same time (black surface).
    if (attempt >= 15) {
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

- (void)openForProcessHandle:(id)processHandle generation:(NSUInteger)generation completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;
    NSString *matchedIdentifier = nil;
    id scene = [self systemDefaultSceneForBundleIdentifier:self.bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if (scene) {
        self.sceneIdentifier = matchedIdentifier;
        SWFileLog(@"SCENE-SYSTEM reuse %@ id=%@", self.bundleIdentifier, matchedIdentifier);
        [self finishOpenForScene:scene generation:generation completion:completion];
        return;
    }

    NSError *error = nil;
    scene = [self createCanonicalDefaultSceneForProcessHandle:processHandle error:&error];
    if (!scene) {
        SWFileLog(@"SCENE-CREATE canonical failed %@ error=%@", self.bundleIdentifier, error);
        completion(nil, error);
        return;
    }
    [self finishOpenForScene:scene generation:generation completion:completion];
}

- (void)pollColdProcessForBundleIdentifier:(NSString *)bundleIdentifier
                                 generation:(NSUInteger)generation
                                    attempt:(NSUInteger)attempt
                                 completion:(SWSceneHostCompletion)completion {
    if (generation != self.openGeneration) return;

    NSString *matchedIdentifier = nil;
    id earlyScene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if (earlyScene) {
        self.sceneIdentifier = matchedIdentifier;
        SWFileLog(@"SCENE-SYSTEM cold-early %@ attempt=%lu id=%@", bundleIdentifier, (unsigned long)attempt, matchedIdentifier);
        [self finishOpenForScene:earlyScene generation:generation completion:completion];
        return;
    }

    id handle = [self processHandleForBundleIdentifier:bundleIdentifier];
    int pid = SWInt0(handle, NSSelectorFromString(@"pid"));
    if (handle && pid > 0) {
        SWFileLog(@"PROC cold ready %@ pid=%d attempts=%lu", bundleIdentifier, pid, (unsigned long)attempt);
        [self openForProcessHandle:handle generation:generation completion:completion];
        return;
    }

    if (attempt >= 100) {
        NSError *error = [NSError errorWithDomain:@"com.dream.splitwindow" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Timed out waiting for the target app process."}];
        self.state = SWSceneHostStateIdle;
        SWFileLog(@"PROC cold timeout %@", bundleIdentifier);
        completion(nil, error);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self pollColdProcessForBundleIdentifier:bundleIdentifier
                                      generation:generation
                                         attempt:attempt + 1
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
    SWFileLog(@"STATE launching %@ foregroundHandoff=%d", bundleIdentifier, foregroundHandoff);

    NSString *matchedIdentifier = nil;
    id existingScene = [self systemDefaultSceneForBundleIdentifier:bundleIdentifier matchedIdentifier:&matchedIdentifier];
    if ([self isSceneUsable:existingScene]) {
        self.sceneIdentifier = matchedIdentifier;
        self.scene = existingScene;
        [self openExistingDefaultScene:existingScene
                            generation:generation
                     foregroundHandoff:foregroundHandoff
                            completion:completion];
        return;
    }

    id handle = [self processHandleForBundleIdentifier:bundleIdentifier];
    int pid = SWInt0(handle, NSSelectorFromString(@"pid"));
    if (handle && pid > 0) {
        SWFileLog(@"PROC warm-no-scene %@ pid=%d", bundleIdentifier, pid);
        [self openForProcessHandle:handle generation:generation completion:completion];
        return;
    }

    [self launchColdWindowed:bundleIdentifier];
    [self pollColdProcessForBundleIdentifier:bundleIdentifier generation:generation attempt:0 completion:completion];
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
