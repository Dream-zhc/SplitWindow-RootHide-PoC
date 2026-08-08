#import "SWOverlayController.h"
#import "SWPreferences.h"
#import "SWSceneHost.h"
#import "SWLogger.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>

static id SWObjMsg0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static id SWObjMsg1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

static BOOL SWSwitcherIsVisible(void) {
    Class switcherClass = NSClassFromString(@"SBMainSwitcherViewController");
    id switcher = SWObjMsg0(switcherClass, NSSelectorFromString(@"sharedInstance"));
    if (!switcher) return NO;
    for (NSString *name in @[@"isVisible", @"isMainSwitcherVisible"]) {
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [switcher methodSignatureForSelector:selector];
        if (![switcher respondsToSelector:selector] || signature.numberOfArguments != 2) continue;
        return ((BOOL (*)(id, SEL))objc_msgSend)(switcher, selector);
    }
    return NO;
}

@interface SWAppButton : UIButton
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SWAppButton
@end

// Small UIKit pass-through window whose behavior is fully controlled here.
// The root view itself never consumes touches; explicit child views (edge
// handle, interaction shield, panel and host) do.
@interface SWFallbackPassThroughWindow : UIWindow
@property (nonatomic, weak) UIView *interactionShieldView;
@property (nonatomic) BOOL consumesRootTouches;
@end

@implementation SWFallbackPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // The system switcher must remain a real system interaction surface. This
    // also lets selecting the windowed app's card hand the same default Scene
    // back to SpringBoard fullscreen instead of trapping taps in our shield.
    if (SWSwitcherIsVisible()) return nil;
    UIView *hit = [super hitTest:point withEvent:event];
    if ((hit == self.rootViewController.view || !hit) &&
        self.consumesRootTouches &&
        self.interactionShieldView &&
        !self.interactionShieldView.hidden) {
        return self.interactionShieldView;
    }
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

@interface SWInteractionShieldView : UIView
@property (nonatomic) BOOL requiresDoubleTap;
@property (nonatomic) BOOL immediateTapMode;
@property (nonatomic, copy) dispatch_block_t tapAction;
@property (nonatomic) BOOL trackingTap;
@property (nonatomic) CGPoint touchStartPoint;
@property (nonatomic) CFTimeInterval previousTapTimestamp;
@property (nonatomic) CGPoint previousTapPoint;
@property (nonatomic) NSUInteger tapResetGeneration;
@end

@implementation SWInteractionShieldView

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *touch = touches.anyObject;
    self.trackingTap = touch != nil;
    if (touch) self.touchStartPoint = [touch locationInView:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *touch = touches.anyObject;
    if (!touch || !self.trackingTap) return;
    CGPoint point = [touch locationInView:self];
    if (hypot(point.x - self.touchStartPoint.x, point.y - self.touchStartPoint.y) > 14.0) {
        self.trackingTap = NO;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    UITouch *touch = touches.anyObject;
    if (!touch || !self.trackingTap) {
        self.trackingTap = NO;
        return;
    }
    self.trackingTap = NO;

    if (self.immediateTapMode || !self.requiresDoubleTap) {
        if (self.tapAction) self.tapAction();
        return;
    }

    CFTimeInterval timestamp = touch.timestamp;
    CGPoint point = [touch locationInView:self];
    BOOL isSecondTap = self.previousTapTimestamp > 0.0 &&
                       (timestamp - self.previousTapTimestamp) <= 0.34 &&
                       hypot(point.x - self.previousTapPoint.x,
                             point.y - self.previousTapPoint.y) <= 44.0;
    if (isSecondTap) {
        self.previousTapTimestamp = 0.0;
        self.tapResetGeneration += 1;
        if (self.tapAction) self.tapAction();
        return;
    }

    self.previousTapTimestamp = timestamp;
    self.previousTapPoint = point;
    NSUInteger generation = ++self.tapResetGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.36 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.tapResetGeneration) return;
        self.previousTapTimestamp = 0.0;
    });
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    self.trackingTap = NO;
}

@end

typedef NS_ENUM(NSInteger, SWOverlaySessionState) {
    SWOverlaySessionStateIdle = 0,
    SWOverlaySessionStateLaunching,
    SWOverlaySessionStateWindowed,
};

@interface SWOverlayController ()
@property (nonatomic) BOOL started;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) SWInteractionShieldView *shieldView;
@property (nonatomic, strong) UIView *handleHitView;
@property (nonatomic, strong) UIView *handleVisual;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UIView *hostContainer;
@property (nonatomic, strong) UIView *sceneLogicalView;
@property (nonatomic, strong) UIView *hostedView;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) SWSceneHost *sceneHost;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property (nonatomic, strong) UIImpactFeedbackGenerator *impactFeedback;
@property (nonatomic, copy) NSString *panelSignature;
@property (nonatomic, copy) NSString *openingBundleIdentifier;
@property (nonatomic) BOOL panelVisible;
@property (nonatomic) BOOL handleOnLeft;
@property (nonatomic) CGFloat handleNormalizedY;
@property (nonatomic) CGFloat preferredScale;
@property (nonatomic) CGFloat effectiveScale;
@property (nonatomic) UIInterfaceOrientation hostContentOrientation;
@property (nonatomic) UIInterfaceOrientation lastEnvironmentOrientation;
@property (nonatomic) NSUInteger orientationDebounceToken;
@property (nonatomic) SWOverlaySessionState sessionState;
@property (nonatomic) CFAbsoluteTime openRequestedAt;
@end

@implementation SWOverlayController

+ (instancetype)sharedInstance {
    static SWOverlayController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SWOverlayController new]; });
    return instance;
}

#pragma mark - SpringBoard environment

- (UIWindowScene *)springBoardWindowScene {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (!(scene.activationState == UISceneActivationStateForegroundActive ||
                  scene.activationState == UISceneActivationStateForegroundInactive)) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            NSString *className = NSStringFromClass(windowScene.class);
            NSString *persistentIdentifier = windowScene.session.persistentIdentifier ?: @"";
            NSString *description = windowScene.description ?: @"";

            if ([persistentIdentifier isEqualToString:@"com.apple.springboard"] ||
                [description containsString:@"identifier: com.apple.springboard"] ||
                ([className isEqualToString:@"SBWindowScene"] &&
                 ![className containsString:@"Aperture"] &&
                 ![className containsString:@"Curtain"])) {
                return windowScene;
            }

            if (!fallback &&
                ![className containsString:@"SystemAperture"] &&
                ![className containsString:@"Curtain"] &&
                ![persistentIdentifier containsString:@"SystemAperture"]) {
                fallback = windowScene;
            }
        }
        return fallback;
    }
    return nil;
}

- (id)frontMostApplication {
    UIApplication *springBoard = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if ([springBoard respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(springBoard, selector);
    }
    return nil;
}

- (NSString *)bundleIdentifierForApplicationLikeObject:(id)object {
    if (!object) return nil;
    for (NSString *name in @[@"bundleIdentifier", @"displayIdentifier"]) {
        id value = SWObjMsg0(object, NSSelectorFromString(name));
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

- (NSString *)frontMostBundleIdentifier {
    return [self bundleIdentifierForApplicationLikeObject:[self frontMostApplication]];
}

- (BOOL)isBundleIdentifierForeground:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return NO;
    id controller = SWObjMsg0(NSClassFromString(@"SBApplicationController"), NSSelectorFromString(@"sharedInstance"));
    id application = SWObjMsg1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    if (!application) application = SWObjMsg1(controller, NSSelectorFromString(@"applicationWithDisplayIdentifier:"), bundleIdentifier);
    if (!application) return NO;

    for (NSString *name in @[@"isForeground", @"isFrontmost", @"isRunningForeground"]) {
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [application methodSignatureForSelector:selector];
        if ([application respondsToSelector:selector] && signature &&
            signature.numberOfArguments == 2 && signature.methodReturnLength == sizeof(BOOL) &&
            ((BOOL (*)(id, SEL))objc_msgSend)(application, selector)) {
            return YES;
        }
    }

    id processState = SWObjMsg0(application, NSSelectorFromString(@"processState"));
    for (NSString *name in @[@"isForeground", @"isFrontmost"]) {
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [processState methodSignatureForSelector:selector];
        if ([processState respondsToSelector:selector] && signature &&
            signature.numberOfArguments == 2 && signature.methodReturnLength == sizeof(BOOL) &&
            ((BOOL (*)(id, SEL))objc_msgSend)(processState, selector)) {
            return YES;
        }
    }

    NSString *description = [[processState description] lowercaseString];
    return [description containsString:@"visibility: foreground"] ||
           [description containsString:@"visibility=foreground"] ||
           [description containsString:@"foregroundrunning"];
}

- (UIInterfaceOrientation)frontMostInterfaceOrientation {
    UIApplication *springBoard = UIApplication.sharedApplication;
    for (NSString *name in @[@"_frontMostAppOrientation",
                             @"frontMostAppOrientation",
                             @"_activeInterfaceOrientation",
                             @"activeInterfaceOrientation"]) {
        SEL selector = NSSelectorFromString(name);
        if (![springBoard respondsToSelector:selector]) continue;
        NSInteger value = ((NSInteger (*)(id, SEL))objc_msgSend)(springBoard, selector);
        if (value >= UIInterfaceOrientationPortrait && value <= UIInterfaceOrientationLandscapeRight) {
            return (UIInterfaceOrientation)value;
        }
    }
    return UIInterfaceOrientationUnknown;
}

- (UIInterfaceOrientation)activeEnvironmentOrientation {
    UIInterfaceOrientation frontMost = [self frontMostInterfaceOrientation];
    if (frontMost != UIInterfaceOrientationUnknown) return frontMost;

    UIWindowScene *scene = [self springBoardWindowScene];
    if (@available(iOS 13.0, *)) {
        if (scene && scene.interfaceOrientation != UIInterfaceOrientationUnknown) return scene.interfaceOrientation;
    }

    switch (UIDevice.currentDevice.orientation) {
        case UIDeviceOrientationLandscapeLeft: return UIInterfaceOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight: return UIInterfaceOrientationLandscapeLeft;
        case UIDeviceOrientationPortraitUpsideDown: return UIInterfaceOrientationPortraitUpsideDown;
        default: return UIInterfaceOrientationPortrait;
    }
}

- (CGRect)activeScreenBounds {
    CGRect bounds = UIScreen.mainScreen.bounds;
    UIInterfaceOrientation orientation = [self activeEnvironmentOrientation];
    if (UIInterfaceOrientationIsLandscape(orientation) && CGRectGetHeight(bounds) > CGRectGetWidth(bounds)) {
        bounds.size = CGSizeMake(CGRectGetHeight(bounds), CGRectGetWidth(bounds));
    } else if (UIInterfaceOrientationIsPortrait(orientation) && CGRectGetWidth(bounds) > CGRectGetHeight(bounds)) {
        bounds.size = CGSizeMake(CGRectGetHeight(bounds), CGRectGetWidth(bounds));
    }
    bounds.origin = CGPointZero;
    return bounds;
}

- (CGFloat)angleForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft: return (CGFloat)M_PI_2;
        case UIInterfaceOrientationLandscapeRight: return (CGFloat)-M_PI_2;
        case UIInterfaceOrientationPortraitUpsideDown: return (CGFloat)M_PI;
        default: return 0.0;
    }
}

- (void)layoutOverlayWindowGeometry {
    if (!self.overlayWindow) return;

    UIWindowScene *scene = self.overlayWindow.windowScene ?: [self springBoardWindowScene];
    UIInterfaceOrientation environment = [self activeEnvironmentOrientation];
    UIInterfaceOrientation sceneOrientation = UIInterfaceOrientationPortrait;
    CGRect sceneBounds = UIScreen.mainScreen.bounds;
    if (@available(iOS 13.0, *)) {
        if (scene && scene.interfaceOrientation != UIInterfaceOrientationUnknown) {
            sceneOrientation = scene.interfaceOrientation;
        }
        if (scene && scene.coordinateSpace) sceneBounds = scene.coordinateSpace.bounds;
    }

    CGRect logicalBounds = [self activeScreenBounds];
    CGFloat delta = [self angleForInterfaceOrientation:environment] -
                    [self angleForInterfaceOrientation:sceneOrientation];
    self.overlayWindow.transform = CGAffineTransformMakeRotation(delta);
    self.overlayWindow.bounds = CGRectMake(0.0,
                                           0.0,
                                           CGRectGetWidth(logicalBounds),
                                           CGRectGetHeight(logicalBounds));
    self.overlayWindow.center = CGPointMake(CGRectGetMidX(sceneBounds), CGRectGetMidY(sceneBounds));
    self.overlayWindow.rootViewController.view.frame = self.overlayWindow.bounds;
    SWFileLog(@"OVERLAY geometry env=%ld scene=%ld delta=%.3f bounds=%@",
              (long)environment,
              (long)sceneOrientation,
              delta,
              NSStringFromCGRect(logicalBounds));
}

- (UIInterfaceOrientation)orientationFromInfoString:(NSString *)value {
    if ([value isEqualToString:@"UIInterfaceOrientationPortrait"]) return UIInterfaceOrientationPortrait;
    if ([value isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) return UIInterfaceOrientationPortraitUpsideDown;
    if ([value isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) return UIInterfaceOrientationLandscapeLeft;
    if ([value isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) return UIInterfaceOrientationLandscapeRight;
    return UIInterfaceOrientationUnknown;
}

- (UIInterfaceOrientation)preferredContentOrientationForBundleIdentifier:(NSString *)bundleIdentifier {
    NSArray *supported = nil;
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    id proxy = SWObjMsg1(proxyClass,
                         NSSelectorFromString(@"applicationProxyForIdentifier:"),
                         bundleIdentifier);
    NSURL *bundleURL = nil;
    @try { bundleURL = [proxy valueForKey:@"bundleURL"]; }
    @catch (__unused NSException *exception) {}

    if ([bundleURL isKindOfClass:[NSURL class]]) {
        NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
        NSDictionary *info = bundle.infoDictionary;
        id value = info[@"UISupportedInterfaceOrientations~iphone"] ?: info[@"UISupportedInterfaceOrientations"];
        if ([value isKindOfClass:[NSArray class]]) supported = value;
    }

    UIInterfaceOrientation environment = [self activeEnvironmentOrientation];
    if (supported.count == 0) return environment;

    NSMutableSet<NSNumber *> *values = [NSMutableSet set];
    for (id item in supported) {
        if (![item isKindOfClass:[NSString class]]) continue;
        UIInterfaceOrientation orientation = [self orientationFromInfoString:item];
        if (orientation != UIInterfaceOrientationUnknown) [values addObject:@(orientation)];
    }
    if ([values containsObject:@(environment)]) return environment;

    BOOL supportsPortrait = [values containsObject:@(UIInterfaceOrientationPortrait)] ||
                            [values containsObject:@(UIInterfaceOrientationPortraitUpsideDown)];
    BOOL supportsLandscape = [values containsObject:@(UIInterfaceOrientationLandscapeLeft)] ||
                             [values containsObject:@(UIInterfaceOrientationLandscapeRight)];
    if (supportsLandscape && !supportsPortrait) {
        UIDeviceOrientation device = UIDevice.currentDevice.orientation;
        if (device == UIDeviceOrientationLandscapeLeft && [values containsObject:@(UIInterfaceOrientationLandscapeRight)]) {
            return UIInterfaceOrientationLandscapeRight;
        }
        if (device == UIDeviceOrientationLandscapeRight && [values containsObject:@(UIInterfaceOrientationLandscapeLeft)]) {
            return UIInterfaceOrientationLandscapeLeft;
        }
        if ([values containsObject:@(UIInterfaceOrientationLandscapeRight)]) return UIInterfaceOrientationLandscapeRight;
        return UIInterfaceOrientationLandscapeLeft;
    }
    if (supportsPortrait) return UIInterfaceOrientationPortrait;

    UIInterfaceOrientation fallback = [self orientationFromInfoString:supported.firstObject];
    return fallback == UIInterfaceOrientationUnknown ? environment : fallback;
}

- (CGRect)hostLogicalBounds {
    CGRect bounds = UIScreen.mainScreen.bounds;
    UIInterfaceOrientation orientation = self.hostContentOrientation;
    if (orientation == UIInterfaceOrientationUnknown) orientation = [self activeEnvironmentOrientation];
    if (UIInterfaceOrientationIsLandscape(orientation) && CGRectGetHeight(bounds) > CGRectGetWidth(bounds)) {
        bounds.size = CGSizeMake(CGRectGetHeight(bounds), CGRectGetWidth(bounds));
    } else if (UIInterfaceOrientationIsPortrait(orientation) && CGRectGetWidth(bounds) > CGRectGetHeight(bounds)) {
        bounds.size = CGSizeMake(CGRectGetHeight(bounds), CGRectGetWidth(bounds));
    }
    bounds.origin = CGPointZero;
    return bounds;
}

- (void)selectionHaptic {
    [self.selectionFeedback prepare];
    [self.selectionFeedback selectionChanged];
}

- (void)lightImpactHaptic {
    [self.impactFeedback prepare];
    [self.impactFeedback impactOccurred];
}

#pragma mark - Window construction

- (UIWindow *)buildSystemOverlayWindow {
    UIWindowScene *scene = [self springBoardWindowScene];
    if (!scene || ![UIWindow instancesRespondToSelector:@selector(initWithWindowScene:)]) return nil;

    // Keep the event router on a tiny UIKit subclass we fully control. Some
    // SpringBoard pass-through window subclasses change hit-test policy across
    // iOS builds; using them here can reintroduce the exact cross-app tap leak
    // this layer exists to prevent.
    Class windowClass = [SWFallbackPassThroughWindow class];
    UIWindow *window = ((id (*)(id, SEL, id))objc_msgSend)([windowClass alloc],
                                                            @selector(initWithWindowScene:),
                                                            scene);
    window.frame = UIScreen.mainScreen.bounds;
    // High enough to stay above normal application scenes, but intentionally
    // below the very-high SpringBoard alert/curtain levels so Control Center,
    // lock UI and emergency/system alerts can still cover SplitWindow.
    window.windowLevel = UIWindowLevelAlert + 80.0;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    SWFileLog(@"OVERLAY window class=%@ scene=%@", NSStringFromClass(windowClass), scene);
    return window;
}

- (void)buildOverlayHierarchy {
    self.overlayWindow = [self buildSystemOverlayWindow];
    if (!self.overlayWindow) return;
    UIView *root = self.overlayWindow.rootViewController.view;

    self.shieldView = [SWInteractionShieldView new];
    self.shieldView.backgroundColor = UIColor.clearColor;
    self.shieldView.userInteractionEnabled = YES;
    self.shieldView.exclusiveTouch = YES;
    self.shieldView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.shieldView.tapAction = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self shieldTapped];
    };
    [root addSubview:self.shieldView];
    if ([self.overlayWindow isKindOfClass:[SWFallbackPassThroughWindow class]]) {
        SWFallbackPassThroughWindow *window = (SWFallbackPassThroughWindow *)self.overlayWindow;
        window.interactionShieldView = self.shieldView;
    }

    self.hostContainer = [UIView new];
    self.hostContainer.backgroundColor = UIColor.clearColor;
    self.hostContainer.layer.cornerRadius = 20.0;
    self.hostContainer.layer.borderWidth = 0.5;
    self.hostContainer.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    self.hostContainer.clipsToBounds = YES;
    self.hostContainer.hidden = YES;
    [root addSubview:self.hostContainer];

    self.sceneLogicalView = [UIView new];
    self.sceneLogicalView.backgroundColor = UIColor.clearColor;
    self.sceneLogicalView.clipsToBounds = NO;
    [self.hostContainer addSubview:self.sceneLogicalView];

    self.resizeHandle = [UIView new];
    self.resizeHandle.backgroundColor = UIColor.clearColor;
    UIImageView *resizeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]];
    resizeIcon.tag = 991;
    resizeIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.58];
    resizeIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.resizeHandle addSubview:resizeIcon];
    UIPanGestureRecognizer *resize = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeHostWindow:)];
    [self.resizeHandle addGestureRecognizer:resize];
    [self.hostContainer addSubview:self.resizeHandle];

    self.panelView = [UIView new];
    self.panelView.backgroundColor = UIColor.clearColor;
    self.panelView.layer.cornerRadius = 26.0;
    self.panelView.layer.borderWidth = 0.5;
    self.panelView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    self.panelView.clipsToBounds = YES;
    self.panelView.hidden = YES;
    [root addSubview:self.panelView];

    self.handleHitView = [UIView new];
    self.handleHitView.backgroundColor = UIColor.clearColor;
    self.handleHitView.userInteractionEnabled = YES;
    [root addSubview:self.handleHitView];

    self.handleVisual = [UIView new];
    self.handleVisual.backgroundColor = [UIColor colorWithWhite:1 alpha:0.76];
    self.handleVisual.layer.cornerRadius = 2.0;
    self.handleVisual.userInteractionEnabled = NO;
    [self.handleHitView addSubview:self.handleVisual];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.28;
    longPress.cancelsTouchesInView = YES;
    [self.handleHitView addGestureRecognizer:longPress];

    UIPanGestureRecognizer *inwardPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleInwardPan:)];
    inwardPan.minimumNumberOfTouches = 1;
    inwardPan.maximumNumberOfTouches = 1;
    inwardPan.cancelsTouchesInView = YES;
    [self.handleHitView addGestureRecognizer:inwardPan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped:)];
    [tap requireGestureRecognizerToFail:longPress];
    [tap requireGestureRecognizerToFail:inwardPan];
    [self.handleHitView addGestureRecognizer:tap];

    self.overlayWindow.hidden = ![SWPreferences enabled];
    [self layoutOverlayWindowGeometry];
    [self layoutAllForCurrentEnvironment];
}

#pragma mark - Lifecycle

- (void)start {
    if (self.started) return;
    SWFileLog(@"START v0.6.1 overlay begin");
    self.sceneHost = [SWSceneHost new];
    self.iconCache = [NSCache new];
    self.iconCache.countLimit = 64;
    self.selectionFeedback = [UISelectionFeedbackGenerator new];
    self.impactFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    self.preferredScale = (CGFloat)[SWPreferences windowScale];
    self.handleOnLeft = [SWPreferences edgeHandleOnLeft];
    self.handleNormalizedY = (CGFloat)[SWPreferences edgeHandleNormalizedY];
    self.hostContentOrientation = UIInterfaceOrientationUnknown;
    self.lastEnvironmentOrientation = [self activeEnvironmentOrientation];
    self.sessionState = SWOverlaySessionStateIdle;

    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(orientationSignal:)
                                               name:UIDeviceOrientationDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(orientationSignal:)
                                               name:UIApplicationDidChangeStatusBarOrientationNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(orientationSignal:)
                                               name:UIScreenModeDidChangeNotification
                                             object:nil];

    [self buildOverlayHierarchy];
    if (!self.overlayWindow) {
        SWFileLog(@"START-FAIL no safe SpringBoard UIWindowScene");
        self.sceneHost = nil;
        return;
    }
    self.started = YES;
    SWFileLog(@"START v0.6.1 overlay ready side=%@ y=%.3f",
              self.handleOnLeft ? @"left" : @"right",
              self.handleNormalizedY);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self prewarmSelectedAppIcons];
    });
}

- (void)reloadPreferences {
    if (!self.started) return;
    BOOL enabled = [SWPreferences enabled];
    self.preferredScale = (CGFloat)[SWPreferences windowScale];
    if (!enabled) {
        [self hidePanel];
        [self dismissHostPreservingScene:YES];
        self.overlayWindow.hidden = YES;
    } else {
        self.overlayWindow.hidden = NO;
        [self configureShieldGesture];
        [self layoutAllForCurrentEnvironment];
    }
    self.panelSignature = nil;
    SWFileLog(@"PREF reload enabled=%d scale=%.3f doubleTap=%d",
              enabled,
              self.preferredScale,
              [SWPreferences dismissRequiresDoubleTap]);
}

#pragma mark - Orientation / app transitions

- (void)orientationSignal:(__unused NSNotification *)notification {
    if (![SWPreferences enabled]) return;
    UIInterfaceOrientation environment = [self activeEnvironmentOrientation];
    if (environment == UIInterfaceOrientationUnknown || environment == self.lastEnvironmentOrientation) return;
    [self scheduleEnvironmentLayout];
}

- (void)scheduleEnvironmentLayout {
    NSUInteger token = ++self.orientationDebounceToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self.orientationDebounceToken) return;
        [self layoutAllForCurrentEnvironment];
    });
}

- (void)frontDisplayDidChange:(id)newDisplay {
    if (!self.started) return;
    if (![SWPreferences enabled]) return;
    NSString *bundleIdentifier = [self frontMostBundleIdentifier];
    if (bundleIdentifier.length == 0) {
        bundleIdentifier = [self bundleIdentifierForApplicationLikeObject:newDisplay];
    }
    if (bundleIdentifier.length == 0) {
        id nestedApplication = SWObjMsg0(newDisplay, NSSelectorFromString(@"application"));
        bundleIdentifier = [self bundleIdentifierForApplicationLikeObject:nestedApplication];
    }
    SWFileLog(@"FRONT display=%@ bundle=%@", newDisplay, bundleIdentifier);

    if (self.panelVisible) [self hidePanel];

    if (self.sessionState == SWOverlaySessionStateWindowed &&
        bundleIdentifier.length > 0 &&
        [bundleIdentifier isEqualToString:self.sceneHost.bundleIdentifier]) {
        [self restoreHostedSceneToSystemFullscreen];
    }
    [self scheduleEnvironmentLayout];
}

#pragma mark - Edge handle + panel geometry

- (CGSize)panelSizeForAppCount:(NSUInteger)count {
    const NSInteger columns = 3;
    const CGFloat cellSize = 52.0;
    const CGFloat padding = 12.0;
    NSInteger rows = MAX(1, (NSInteger)((count + columns - 1) / columns));
    NSInteger visibleRows = MIN(rows, 4);
    return CGSizeMake(columns * cellSize + padding * 2.0,
                      visibleRows * cellSize + padding * 2.0);
}

- (CGFloat)clampedHandleCenterYForPanelHeight:(CGFloat)panelHeight {
    CGRect screen = [self activeScreenBounds];
    CGFloat centerY = CGRectGetHeight(screen) * self.handleNormalizedY;
    CGFloat safe = 12.0;
    CGFloat halfHandle = 40.0;
    CGFloat halfPanel = panelHeight > 0 ? panelHeight * 0.5 : 0.0;
    CGFloat margin = MAX(halfHandle, halfPanel) + safe;
    centerY = MAX(margin, MIN(centerY, CGRectGetHeight(screen) - margin));
    return centerY;
}

- (CGRect)snappedHandleFrameForPanelHeight:(CGFloat)panelHeight {
    CGRect screen = [self activeScreenBounds];
    CGFloat width = 24.0;
    CGFloat height = 80.0;
    CGFloat x = self.handleOnLeft ? 0.0 : CGRectGetWidth(screen) - width;
    CGFloat centerY = [self clampedHandleCenterYForPanelHeight:panelHeight];
    return CGRectMake(x, floor(centerY - height * 0.5), width, height);
}

- (void)layoutHandleAnimated:(BOOL)animated panelHeight:(CGFloat)panelHeight {
    CGRect frame = [self snappedHandleFrameForPanelHeight:panelHeight];
    void (^block)(void) = ^{
        self.handleHitView.frame = frame;
        CGFloat visualX = self.handleOnLeft ? 4.0 : CGRectGetWidth(frame) - 8.0;
        self.handleVisual.frame = CGRectMake(visualX, 11.0, 4.0, 58.0);
    };
    if (animated) {
        [UIView animateWithDuration:0.18
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:block
                         completion:nil];
    } else {
        block();
    }
}

- (CGRect)panelFrameForSize:(CGSize)size {
    CGRect screen = [self activeScreenBounds];
    CGRect handleFrame = [self snappedHandleFrameForPanelHeight:size.height];
    CGFloat gap = 8.0;
    CGFloat x = self.handleOnLeft
        ? CGRectGetMaxX(handleFrame) + gap
        : CGRectGetMinX(handleFrame) - gap - size.width;
    CGFloat centerY = CGRectGetMidY(handleFrame);
    CGFloat y = centerY - size.height * 0.5;
    CGRect frame = CGRectMake(floor(x), floor(y), size.width, size.height);
    // The handle center is clamped before this calculation, therefore this
    // clamp should be a no-op. Keep it as a defensive guard only.
    frame.origin.x = MAX(4.0, MIN(frame.origin.x, CGRectGetWidth(screen) - size.width - 4.0));
    return frame;
}

- (void)handleTapped:(__unused UITapGestureRecognizer *)gesture {
    if (self.panelVisible) {
        [self selectionHaptic];
        [self hidePanel];
    } else {
        [self showPanel];
    }
}

- (void)handleInwardPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.handleHitView];
    CGPoint velocity = [gesture velocityInView:self.handleHitView];
    CGFloat inward = self.handleOnLeft ? translation.x : -translation.x;
    CGFloat inwardVelocity = self.handleOnLeft ? velocity.x : -velocity.x;
    CGFloat vertical = fabs(translation.y);

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self selectionHaptic];
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        // A small elastic travel makes the edge affordance feel attached to the
        // finger without moving its persisted anchor. Long-press remains the
        // dedicated gesture for relocating the handle itself.
        if (inward > 0.0 && fabs(inward) >= vertical * 0.55) {
            CGFloat travel = MIN(12.0, inward * 0.22);
            self.handleHitView.transform = CGAffineTransformMakeTranslation(self.handleOnLeft ? travel : -travel, 0.0);
        }
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.handleHitView.transform = CGAffineTransformIdentity;
        BOOL horizontalIntent = fabs(inward) >= vertical * 0.55;
        BOOL shouldOpen = !self.panelVisible && horizontalIntent &&
                          (inward >= 20.0 || inwardVelocity >= 260.0);
        BOOL shouldClose = self.panelVisible && horizontalIntent &&
                           (inward <= -20.0 || inwardVelocity <= -260.0);
        if (shouldOpen) {
            [self showPanel];
        } else if (shouldClose) {
            [self hidePanel];
        } else {
            [self layoutHandleAnimated:YES panelHeight:self.panelVisible ? CGRectGetHeight(self.panelView.bounds) : 0.0];
        }
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    UIView *root = self.overlayWindow.rootViewController.view;
    CGPoint location = [gesture locationInView:root];
    CGRect screen = [self activeScreenBounds];
    CGFloat width = 24.0;
    CGFloat height = 80.0;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self lightImpactHaptic];
        if (self.panelVisible) [self hidePanel];
    }

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat centerY = MAX(52.0, MIN(location.y, CGRectGetHeight(screen) - 52.0));
        CGFloat x = MAX(0.0, MIN(location.x - width * 0.5, CGRectGetWidth(screen) - width));
        self.handleHitView.frame = CGRectMake(x, centerY - height * 0.5, width, height);
        CGFloat visualX = CGRectGetMidX(self.handleHitView.bounds) - 2.0;
        self.handleVisual.frame = CGRectMake(visualX, 11.0, 4.0, 58.0);
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.handleOnLeft = CGRectGetMidX(self.handleHitView.frame) < CGRectGetWidth(screen) * 0.5;
        self.handleNormalizedY = CGRectGetMidY(self.handleHitView.frame) / MAX(1.0, CGRectGetHeight(screen));
        self.handleNormalizedY = MAX(0.10, MIN(self.handleNormalizedY, 0.90));
        [SWPreferences setEdgeHandleOnLeft:self.handleOnLeft normalizedY:self.handleNormalizedY];
        [self layoutHandleAnimated:YES panelHeight:0];
        [self selectionHaptic];
        SWFileLog(@"HANDLE snap side=%@ y=%.3f",
                  self.handleOnLeft ? @"left" : @"right",
                  self.handleNormalizedY);
    }
}

- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier {
    id controller = SWObjMsg0(NSClassFromString(@"SBApplicationController"), NSSelectorFromString(@"sharedInstance"));
    id app = SWObjMsg1(controller, NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    for (NSString *key in @[@"displayName", @"localizedName", @"name"]) {
        @try {
            id value = [app valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        } @catch (__unused NSException *exception) {}
    }
    return bundleIdentifier;
}

- (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return nil;
    UIImage *cached = [self.iconCache objectForKey:bundleIdentifier];
    if (cached) return cached;

    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:selector]) {
        UIImage *image = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(UIImage.class,
                                                                                 selector,
                                                                                 bundleIdentifier,
                                                                                 10,
                                                                                 UIScreen.mainScreen.scale);
        if ([image isKindOfClass:[UIImage class]]) {
            CGSize size = CGSizeMake(40.0, 40.0);
            UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
            [image drawInRect:(CGRect){CGPointZero, size}];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            UIImage *result = [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            if (result) [self.iconCache setObject:result forKey:bundleIdentifier];
            return result;
        }
    }
    return [UIImage systemImageNamed:@"app.fill"];
}

- (void)prewarmSelectedAppIcons {
    if (![SWPreferences enabled]) return;
    NSArray<NSString *> *bundleIdentifiers = [SWPreferences selectedBundleIdentifiers];
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        (void)[self iconForBundleIdentifier:bundleIdentifier];
    }
    SWFileLog(@"PERF panel icons prewarmed count=%lu", (unsigned long)bundleIdentifiers.count);
}

- (void)rebuildPanelIfNeeded {
    NSArray<NSString *> *apps = [SWPreferences selectedBundleIdentifiers];
    CGSize size = [self panelSizeForAppCount:apps.count];
    CGRect screen = [self activeScreenBounds];
    NSString *signature = [NSString stringWithFormat:@"%@|%.0fx%.0f",
                           [apps componentsJoinedByString:@"|"],
                           CGRectGetWidth(screen),
                           CGRectGetHeight(screen)];

    [self layoutHandleAnimated:NO panelHeight:size.height];
    self.panelView.frame = [self panelFrameForSize:size];
    self.handleNormalizedY = CGRectGetMidY(self.handleHitView.frame) / MAX(1.0, CGRectGetHeight(screen));

    if ([self.panelSignature isEqualToString:signature] && self.panelView.subviews.count > 0) return;
    self.panelSignature = signature;

    [self.panelView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    blur.frame = self.panelView.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panelView addSubview:blur];

    const NSInteger columns = 3;
    const CGFloat cellSize = 52.0;
    const CGFloat padding = 12.0;
    NSInteger rows = MAX(1, (NSInteger)((apps.count + columns - 1) / columns));
    NSInteger visibleRows = MIN(rows, 4);
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectInset(self.panelView.bounds, padding, padding)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = rows > visibleRows;
    [self.panelView addSubview:scroll];

    [apps enumerateObjectsUsingBlock:^(NSString *bundleID, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSInteger row = (NSInteger)index / columns;
        NSInteger column = (NSInteger)index % columns;
        CGFloat buttonSize = 48.0;
        CGFloat x = column * cellSize + (cellSize - buttonSize) * 0.5;
        CGFloat y = row * cellSize + (cellSize - buttonSize) * 0.5;
        SWAppButton *button = [SWAppButton buttonWithType:UIButtonTypeCustom];
        button.bundleIdentifier = bundleID;
        button.frame = CGRectMake(x, y, buttonSize, buttonSize);
        button.backgroundColor = UIColor.clearColor;
        button.layer.cornerRadius = 13.0;
        button.accessibilityLabel = [self displayNameForBundleIdentifier:bundleID];
        UIImage *icon = [self iconForBundleIdentifier:bundleID];
        if (icon) {
            [button setImage:icon forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        }
        [button addTarget:self action:@selector(appButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:button];
    }];
    scroll.contentSize = CGSizeMake(CGRectGetWidth(scroll.bounds), rows * cellSize);
}

- (void)showPanel {
    if (![SWPreferences enabled]) return;
    [self rebuildPanelIfNeeded];
    self.panelVisible = YES;
    self.panelView.hidden = NO;
    self.panelView.alpha = 0.18;
    CGFloat initialOffset = self.handleOnLeft ? -34.0 : 34.0;
    self.panelView.transform = CGAffineTransformMakeTranslation(initialOffset, 0.0);
    [self updateInteractionShield];
    [UIView animateWithDuration:0.26
                          delay:0.0
         usingSpringWithDamping:0.88
          initialSpringVelocity:0.15
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.panelView.alpha = 1.0;
        self.panelView.transform = CGAffineTransformIdentity;
    } completion:nil];
    [self lightImpactHaptic];
    SWFileLog(@"PANEL show side=%@ handleCenterY=%.1f panelCenterY=%.1f",
              self.handleOnLeft ? @"left" : @"right",
              CGRectGetMidY(self.handleHitView.frame),
              CGRectGetMidY(self.panelView.frame));
}

- (void)hidePanel {
    if (!self.panelVisible && self.panelView.hidden) return;
    self.panelVisible = NO;
    self.panelView.hidden = YES;
    self.panelView.transform = CGAffineTransformIdentity;
    self.panelView.alpha = 1.0;
    [self layoutHandleAnimated:NO panelHeight:0];
    [self updateInteractionShield];
    SWFileLog(@"PANEL hide");
}

- (void)appButtonTapped:(SWAppButton *)sender {
    NSString *bundleIdentifier = sender.bundleIdentifier;
    if (bundleIdentifier.length == 0) return;
    [self lightImpactHaptic];
    [self hidePanel];
    if (self.sessionState == SWOverlaySessionStateWindowed &&
        [self.sceneHost.bundleIdentifier isEqualToString:bundleIdentifier]) {
        SWFileLog(@"OPEN noop already-windowed %@", bundleIdentifier);
        return;
    }
    [self openBundleIdentifier:bundleIdentifier];
}

#pragma mark - Interaction shield

- (void)configureShieldGesture {
    self.shieldView.immediateTapMode = self.panelVisible;
    self.shieldView.requiresDoubleTap = !self.panelVisible && [SWPreferences dismissRequiresDoubleTap];
    self.shieldView.previousTapTimestamp = 0.0;
    self.shieldView.tapResetGeneration += 1;
}

- (void)updateInteractionShield {
    // Do not freeze the foreground app while a cold/background launch is still
    // preparing its Scene. The shield is needed only for a visible picker or a
    // visible mini-window, where outside gestures have SplitWindow semantics.
    BOOL shouldShow = self.panelVisible || self.sessionState == SWOverlaySessionStateWindowed;
    self.shieldView.hidden = !shouldShow;
    self.shieldView.frame = self.overlayWindow.rootViewController.view.bounds;
    [self configureShieldGesture];
    if ([self.overlayWindow isKindOfClass:[SWFallbackPassThroughWindow class]]) {
        ((SWFallbackPassThroughWindow *)self.overlayWindow).consumesRootTouches = shouldShow;
    }

    UIView *root = self.overlayWindow.rootViewController.view;
    if (self.panelVisible) {
        // Picker is modal over the mini-window: every tap outside the picker,
        // including a tap on the hosted app, must close only the picker and be
        // consumed. Keep the shield above the host but below picker + handle.
        if (!self.hostContainer.hidden) [root bringSubviewToFront:self.hostContainer];
        [root bringSubviewToFront:self.shieldView];
        [root bringSubviewToFront:self.panelView];
    } else {
        // Normal windowed mode: shield owns only the area outside the hosted
        // surface, so the app itself remains fully interactive.
        if (!self.shieldView.hidden) [root sendSubviewToBack:self.shieldView];
        if (!self.hostContainer.hidden) [root bringSubviewToFront:self.hostContainer];
    }
    [root bringSubviewToFront:self.handleHitView];
}

- (void)shieldTapped {
    // Modal priority: an open app picker owns the first outside tap. It closes
    // only the picker; the mini-window underneath stays alive.
    if (self.panelVisible) {
        // Keep the shield alive until the complete touch sequence has left the
        // event router. Hiding the overlay in the same touchesEnded callback can
        // expose the underlying app during cross-scene dispatch on iOS 16.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.018 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.panelVisible) [self hidePanel];
        });
        return;
    }
    if (self.sessionState == SWOverlaySessionStateWindowed) {
        [self lightImpactHaptic];
        SWFileLog(@"TOUCH shield dismiss double=%d", [SWPreferences dismissRequiresDoubleTap]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.018 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.sessionState == SWOverlaySessionStateWindowed && !self.panelVisible) {
                [self dismissHostPreservingScene:YES];
            }
        });
    }
}

#pragma mark - Mini-window layout / scaling

- (CGFloat)clampedPreferredScale:(CGFloat)scale {
    return MAX(0.32, MIN(scale, 0.95));
}

- (CGFloat)fitScaleForLogicalBounds:(CGRect)logical screenBounds:(CGRect)screen {
    CGFloat availableWidth = MAX(1.0, CGRectGetWidth(screen) - 24.0);
    CGFloat availableHeight = MAX(1.0, CGRectGetHeight(screen) - 48.0);
    CGFloat fit = MIN(availableWidth / MAX(1.0, CGRectGetWidth(logical)),
                      availableHeight / MAX(1.0, CGRectGetHeight(logical)));
    return MAX(0.20, MIN(fit, 0.95));
}

- (CGRect)hostFrameForCurrentScale {
    CGRect screen = [self activeScreenBounds];
    CGRect logical = [self hostLogicalBounds];
    CGFloat fitScale = [self fitScaleForLogicalBounds:logical screenBounds:screen];
    self.effectiveScale = MIN([self clampedPreferredScale:self.preferredScale], fitScale);
    CGFloat width = ceil(CGRectGetWidth(logical) * self.effectiveScale);
    CGFloat height = ceil(CGRectGetHeight(logical) * self.effectiveScale);
    CGFloat x = floor((CGRectGetWidth(screen) - width) * 0.5);
    CGFloat y = floor((CGRectGetHeight(screen) - height) * 0.5);
    return CGRectMake(x, y, width, height);
}

- (void)layoutHostContainer {
    if (!self.hostContainer) return;
    CGRect logical = [self hostLogicalBounds];
    CGRect hostFrame = [self hostFrameForCurrentScale];
    self.hostContainer.frame = hostFrame;

    self.sceneLogicalView.bounds = logical;
    self.sceneLogicalView.layer.anchorPoint = CGPointZero;
    self.sceneLogicalView.layer.position = CGPointZero;
    self.sceneLogicalView.transform = CGAffineTransformMakeScale(self.effectiveScale, self.effectiveScale);

    if (self.hostedView) {
        self.hostedView.transform = CGAffineTransformIdentity;
        self.hostedView.frame = logical;
        self.hostedView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }

    CGFloat handleSize = 32.0;
    self.resizeHandle.frame = CGRectMake(MAX(0.0, CGRectGetWidth(self.hostContainer.bounds) - handleSize),
                                         MAX(0.0, CGRectGetHeight(self.hostContainer.bounds) - handleSize),
                                         handleSize,
                                         handleSize);
    UIImageView *resizeIcon = [self.resizeHandle viewWithTag:991];
    resizeIcon.frame = CGRectMake(9, 9, 14, 14);
    [self.hostContainer bringSubviewToFront:self.resizeHandle];
}

- (void)resizeHostWindow:(UIPanGestureRecognizer *)gesture {
    if (self.sessionState != SWOverlaySessionStateWindowed) return;
    UIView *root = self.overlayWindow.rootViewController.view;
    CGPoint translation = [gesture translationInView:root];
    CGRect logical = [self hostLogicalBounds];
    CGFloat denominator = MAX(180.0, MIN(CGRectGetWidth(logical), CGRectGetHeight(logical)));
    CGFloat delta = (translation.x + translation.y) * 0.5 / denominator;
    if (fabs(delta) > 0.0001) {
        CGFloat newScale = [self clampedPreferredScale:self.preferredScale + delta];
        if (fabs(newScale - self.preferredScale) >= 0.0015) {
            self.preferredScale = newScale;
            [self layoutHostContainer];
        }
        [gesture setTranslation:CGPointZero inView:root];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [SWPreferences setWindowScale:self.preferredScale];
        [self selectionHaptic];
        SWFileLog(@"HOST resize preferred=%.3f effective=%.3f", self.preferredScale, self.effectiveScale);
    }
}

#pragma mark - Scene lifecycle

- (void)openBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0 || ![SWPreferences enabled]) return;
    NSString *frontMost = [self frontMostBundleIdentifier];
    BOOL detectedForeground = [self isBundleIdentifierForeground:bundleIdentifier];
    BOOL foregroundHandoff = [frontMost isEqualToString:bundleIdentifier] || detectedForeground;
    SWFileLog(@"OPEN request %@ front=%@ detectedForeground=%d foregroundHandoff=%d",
              bundleIdentifier,
              frontMost,
              detectedForeground,
              foregroundHandoff);

    self.openRequestedAt = CFAbsoluteTimeGetCurrent();
    self.openingBundleIdentifier = bundleIdentifier;
    self.hostContentOrientation = [self preferredContentOrientationForBundleIdentifier:bundleIdentifier];
    self.sessionState = SWOverlaySessionStateLaunching;
    self.hostContainer.hidden = YES;
    [self.hostedView removeFromSuperview];
    self.hostedView = nil;
    [self updateInteractionShield];

    __weak typeof(self) weakSelf = self;
    [self.sceneHost openBundleIdentifier:bundleIdentifier
                       foregroundHandoff:foregroundHandoff
                              completion:^(UIView *hostedView, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (![self.openingBundleIdentifier isEqualToString:bundleIdentifier]) return;
        if (error || !hostedView) {
            self.sessionState = SWOverlaySessionStateIdle;
            self.openingBundleIdentifier = nil;
            [self updateInteractionShield];
            [self showFailureBubble:error.localizedDescription ?: @"Default Scene host failed"];
            SWFileLog(@"OPEN failed %@ error=%@", bundleIdentifier, error);
            return;
        }
        [self attachHostedView:hostedView bundleIdentifier:bundleIdentifier];
    }];
}

- (void)attachHostedView:(UIView *)hostedView bundleIdentifier:(NSString *)bundleIdentifier {
    [self.hostedView removeFromSuperview];
    self.hostedView = hostedView;
    hostedView.userInteractionEnabled = YES;
    hostedView.transform = CGAffineTransformIdentity;
    [self.sceneLogicalView insertSubview:hostedView atIndex:0];

    CGRect logical = [self hostLogicalBounds];
    UIInterfaceOrientation contentOrientation = self.hostContentOrientation;
    if (contentOrientation == UIInterfaceOrientationUnknown) contentOrientation = [self activeEnvironmentOrientation];
    // Lay out the remote presentation at its final full-screen logical size
    // before foregrounding the real system Scene. This lets the first committed
    // client surface (native launch screen / warm snapshot) arrive already in
    // the correctly scaled window instead of racing an empty host.
    [self layoutHostContainer];
    [self.sceneLogicalView layoutIfNeeded];
    [hostedView layoutIfNeeded];
    [self.sceneHost updateSceneForHostBounds:logical interfaceOrientation:contentOrientation];

    // No synthetic black shell / spinner. The container becomes visible only
    // after the native default Scene has a presentation view and one main-queue
    // turn to connect its remote surface (LaunchScreen on a true cold start).
    self.hostContainer.hidden = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hostedView != hostedView || ![self.openingBundleIdentifier isEqualToString:bundleIdentifier]) return;
        self.sessionState = SWOverlaySessionStateWindowed;
        self.hostContainer.alpha = 0.0;
        self.hostContainer.transform = CGAffineTransformMakeScale(0.965, 0.965);
        self.hostContainer.hidden = NO;
        self.openingBundleIdentifier = nil;
        [self updateInteractionShield];
        CFAbsoluteTime elapsed = (CFAbsoluteTimeGetCurrent() - self.openRequestedAt) * 1000.0;
        SWFileLog(@"PERF visible %@ %.0fms frame=%@", bundleIdentifier, elapsed, NSStringFromCGRect(self.hostContainer.frame));
        [UIView animateWithDuration:0.20
                              delay:0.0
             usingSpringWithDamping:0.92
              initialSpringVelocity:0.10
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.hostContainer.alpha = 1.0;
            self.hostContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

- (void)dismissHostPreservingScene:(BOOL)preserveScene {
    if (self.sessionState == SWOverlaySessionStateIdle && self.hostContainer.hidden) return;
    NSString *bundle = self.sceneHost.bundleIdentifier;
    self.openingBundleIdentifier = nil;
    self.sessionState = SWOverlaySessionStateIdle;
    self.hostContainer.hidden = YES;
    self.hostContainer.alpha = 1.0;
    self.hostContainer.transform = CGAffineTransformIdentity;
    [self.hostedView removeFromSuperview];
    self.hostedView = nil;
    if (preserveScene) [self.sceneHost dismissPresentationPreservingScene];
    else [self.sceneHost close];
    [self updateInteractionShield];
    SWFileLog(@"HOST dismiss %@ preserve=%d", bundle, preserveScene);
}

- (void)restoreHostedSceneToSystemFullscreen {
    if (self.sessionState != SWOverlaySessionStateWindowed) return;
    NSString *bundle = self.sceneHost.bundleIdentifier;
    self.sessionState = SWOverlaySessionStateIdle;
    self.openingBundleIdentifier = nil;
    self.hostContainer.hidden = YES;
    [self.hostedView removeFromSuperview];
    self.hostedView = nil;
    [self.sceneHost relinquishPresentationForSystemForeground];
    [self updateInteractionShield];
    SWFileLog(@"HOST restore-fullscreen %@", bundle);
}

#pragma mark - Global layout

- (void)layoutAllForCurrentEnvironment {
    if (!self.overlayWindow) return;
    UIInterfaceOrientation environment = [self activeEnvironmentOrientation];
    CGRect screen = [self activeScreenBounds];
    [self layoutOverlayWindowGeometry];
    self.shieldView.frame = self.overlayWindow.bounds;

    if (self.sceneHost.bundleIdentifier.length > 0) {
        self.hostContentOrientation = [self preferredContentOrientationForBundleIdentifier:self.sceneHost.bundleIdentifier];
    }

    if (self.panelVisible) [self rebuildPanelIfNeeded];
    else [self layoutHandleAnimated:NO panelHeight:0];

    if (self.sessionState == SWOverlaySessionStateWindowed && !self.hostContainer.hidden) {
        [self layoutHostContainer];
        CGRect logical = [self hostLogicalBounds];
        UIInterfaceOrientation content = self.hostContentOrientation;
        if (content == UIInterfaceOrientationUnknown) content = environment;
        [self.sceneHost updateSceneForHostBounds:logical interfaceOrientation:content];
    }

    self.lastEnvironmentOrientation = environment;
    [self updateInteractionShield];
    SWFileLog(@"UI layout environment=%ld bounds=%@ handle=%@ panel=%d host=%d",
              (long)environment,
              NSStringFromCGRect(screen),
              self.handleOnLeft ? @"left" : @"right",
              self.panelVisible,
              self.sessionState == SWOverlaySessionStateWindowed);
}

#pragma mark - Failure UI

- (void)showFailureBubble:(NSString *)message {
    UIView *root = self.overlayWindow.rootViewController.view;
    UIView *old = [root viewWithTag:46001];
    [old removeFromSuperview];
    CGRect screen = [self activeScreenBounds];
    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(24.0, 74.0, MAX(120.0, CGRectGetWidth(screen) - 48.0), 58.0)];
    bubble.tag = 46001;
    bubble.backgroundColor = [UIColor colorWithRed:0.42 green:0.07 blue:0.07 alpha:0.96];
    bubble.layer.cornerRadius = 14.0;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(bubble.bounds, 12.0, 8.0)];
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    [bubble addSubview:label];
    [root addSubview:bubble];
    [root bringSubviewToFront:bubble];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [bubble removeFromSuperview];
    });
}

@end
