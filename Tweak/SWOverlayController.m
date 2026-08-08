#import "SWOverlayController.h"
#import "SWPreferences.h"
#import "SWSceneHost.h"
#import "SWLogger.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

@interface SWAppButton : UIButton
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SWAppButton
@end

@interface SWOverlayController ()
@property (nonatomic) BOOL started;
@property (nonatomic, strong) UIWindow *edgeWindow;
@property (nonatomic, strong) UIWindow *floatingWindow;
@property (nonatomic, strong) UIWindow *panelWindow;
@property (nonatomic, strong) UIWindow *backdropWindow;
@property (nonatomic, strong) UIWindow *hostWindow;
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) UIView *sceneClipView;
@property (nonatomic, strong) UIView *hostedView;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) SWSceneHost *sceneHost;
@property (nonatomic, strong) UILabel *hostTitleLabel;
@property (nonatomic, strong) UIImageView *hostIconView;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property (nonatomic, copy) NSString *panelSignature;
@property (nonatomic) CGFloat hostScale;
@property (nonatomic) CGPoint hostNormalizedCenter;
@end

@implementation SWOverlayController

+ (instancetype)sharedInstance {
    static SWOverlayController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SWOverlayController new]; });
    return instance;
}

- (UIWindowScene *)springBoardWindowScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (scene.activationState == UISceneActivationStateForegroundActive ||
                scene.activationState == UISceneActivationStateForegroundInactive) {
                return windowScene;
            }
        }
    }
    return nil;
}

- (CGRect)activeScreenBounds {
    UIWindowScene *scene = [self springBoardWindowScene];
    if (@available(iOS 13.0, *)) {
        if (scene && scene.coordinateSpace) return scene.coordinateSpace.bounds;
    }
    return UIScreen.mainScreen.bounds;
}

- (UIInterfaceOrientation)activeInterfaceOrientation {
    UIWindowScene *scene = [self springBoardWindowScene];
    if (@available(iOS 13.0, *)) {
        if (scene) return scene.interfaceOrientation;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)deviceOrientationDidChange:(__unused NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutOverlayWindowsForCurrentOrientation];
    });
}

- (void)layoutOverlayWindowsForCurrentOrientation {
    CGRect screen = [self activeScreenBounds];
    if (self.edgeWindow) {
        self.edgeWindow.frame = CGRectMake(CGRectGetWidth(screen) - 14.0, 0, 14.0, CGRectGetHeight(screen));
        UIView *edge = self.edgeWindow.rootViewController.view;
        UIView *handle = edge.subviews.firstObject;
        if (handle) {
            handle.frame = CGRectMake(8.0,
                                      floor((CGRectGetHeight(screen) - 64.0) * 0.42),
                                      4.0,
                                      64.0);
        }
    }

    if (self.floatingWindow) {
        CGFloat size = 46.0;
        self.floatingWindow.frame = CGRectMake(CGRectGetWidth(screen) - size - 10.0,
                                               MAX(30.0, CGRectGetHeight(screen) * 0.42),
                                               size,
                                               size);
    }

    if (self.backdropWindow && !self.backdropWindow.hidden) self.backdropWindow.frame = screen;
    self.panelSignature = nil;
    if (self.panelWindow && !self.panelWindow.hidden) [self rebuildPanel];
    if (self.hostWindow && !self.hostWindow.hidden) {
        [self layoutHostWindowAnimated:NO];
        [self.sceneHost updateSceneForHostBounds:screen interfaceOrientation:[self activeInterfaceOrientation]];
    }
    SWFileLog(@"UI rotation layout orientation=%ld bounds=%@",
              (long)[self activeInterfaceOrientation],
              NSStringFromCGRect(screen));
}

- (UIWindow *)windowWithFrame:(CGRect)frame level:(CGFloat)level {
    SWFileLog(@"UI-1 create window requested frame=%@ level=%.1f", NSStringFromCGRect(frame), level);
    UIWindowScene *scene = [self springBoardWindowScene];
    if (!scene || ![UIWindow instancesRespondToSelector:@selector(initWithWindowScene:)]) {
        SWFileLog(@"UI-2 refused window creation: no foreground SpringBoard UIWindowScene");
        return nil;
    }
    SWFileLog(@"UI-2 selected SpringBoard UIWindowScene=%@ state=%ld", scene, (long)scene.activationState);
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = frame;
    window.windowLevel = level;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    return window;
}

- (void)start {
    if (self.started) return;
    SWFileLog(@"START-1 explicit overlay start begin");
    self.sceneHost = [SWSceneHost new];
    self.iconCache = [NSCache new];
    self.iconCache.countLimit = 64;
    self.hostScale = (CGFloat)[SWPreferences windowScale];
    self.hostNormalizedCenter = CGPointMake(0.5, 0.5);
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(deviceOrientationDidChange:)
                                               name:UIDeviceOrientationDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(deviceOrientationDidChange:)
                                               name:UIApplicationDidChangeStatusBarOrientationNotification
                                             object:nil];
    SWFileLog(@"START-2 building edge window");
    [self buildEdgeWindow];
    if (!self.edgeWindow) {
        SWFileLog(@"START-FAIL no safe foreground UIWindowScene for edge window");
        self.sceneHost = nil;
        return;
    }
    SWFileLog(@"START-3 building floating window");
    [self buildFloatingWindow];
    if (!self.floatingWindow) {
        SWFileLog(@"START-FAIL no safe foreground UIWindowScene for floating window");
        self.edgeWindow.hidden = YES;
        self.edgeWindow.rootViewController = nil;
        self.edgeWindow = nil;
        self.sceneHost = nil;
        return;
    }
    self.started = YES;
    self.edgeWindow.hidden = NO;
    self.floatingWindow.hidden = ![SWPreferences showFloatingButton];
    SWFileLog(@"START-4 explicit activation windows visible floating=%d", !self.floatingWindow.hidden);
    SWFileLog(@"START-5 overlay controller started");
}

- (void)buildEdgeWindow {
    CGRect screen = [self activeScreenBounds];
    self.edgeWindow = [self windowWithFrame:CGRectMake(CGRectGetWidth(screen) - 14.0, 0, 14.0, CGRectGetHeight(screen)) level:UIWindowLevelAlert + 70.0];

    UIView *edge = self.edgeWindow.rootViewController.view;
    edge.backgroundColor = UIColor.clearColor;

    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(8.0,
                                                              floor((CGRectGetHeight(screen) - 64.0) * 0.42),
                                                              4.0,
                                                              64.0)];
    handle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    handle.layer.cornerRadius = 2.0;
    handle.userInteractionEnabled = NO;
    [edge addSubview:handle];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(edgePan:)];
    [edge addGestureRecognizer:pan];
    self.edgeWindow.hidden = NO;
}

- (void)buildFloatingWindow {
    CGRect screen = [self activeScreenBounds];
    CGFloat size = 46.0;
    self.floatingWindow = [self windowWithFrame:CGRectMake(CGRectGetWidth(screen) - size - 10.0,
                                                           CGRectGetHeight(screen) * 0.42,
                                                           size, size)
                                             level:UIWindowLevelAlert + 60.0];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = self.floatingWindow.bounds;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    button.tintColor = UIColor.whiteColor;
    button.layer.cornerRadius = size / 2.0;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    if (@available(iOS 13.0, *)) {
        UIImage *image = [UIImage systemImageNamed:@"square.grid.2x2.fill"];
        [button setImage:image forState:UIControlStateNormal];
    } else {
        [button setTitle:@"▦" forState:UIControlStateNormal];
    }
    [button addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingWindow.rootViewController.view addSubview:button];

    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloatingButton:)];
    [button addGestureRecognizer:drag];
}

- (void)reloadPreferences {
    if (!self.started) return;
    BOOL enabled = [SWPreferences enabled];
    self.panelSignature = nil;
    if (self.backdropWindow) [self configureBackdropGesture];
    self.edgeWindow.hidden = !enabled;
    self.floatingWindow.hidden = !(enabled && [SWPreferences showFloatingButton]);
    if (!enabled) {
        [self hidePanel];
        [self closeHostWindow];
    } else if (self.panelWindow && !self.panelWindow.hidden) {
        [self rebuildPanel];
    }
    SWFileLog(@"PREF reloaded enabled=%d floating=%d apps=%@", enabled, [SWPreferences showFloatingButton], [SWPreferences selectedBundleIdentifiers]);
}

- (void)edgePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:gesture.view];
    if (gesture.state == UIGestureRecognizerStateEnded && translation.x < -28.0) {
        [self showPanel];
    }
}

- (void)dragFloatingButton:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.floatingWindow;
    CGPoint translation = [gesture translationInView:window];
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        CGRect frame = window.frame;
        frame.origin.x += translation.x;
        frame.origin.y += translation.y;
        CGRect screen = [self activeScreenBounds];
        frame.origin.x = MAX(4.0, MIN(frame.origin.x, CGRectGetWidth(screen) - CGRectGetWidth(frame) - 4.0));
        frame.origin.y = MAX(30.0, MIN(frame.origin.y, CGRectGetHeight(screen) - CGRectGetHeight(frame) - 30.0));
        window.frame = frame;
        [gesture setTranslation:CGPointZero inView:window];
    }
}

- (void)togglePanel {
    if (self.panelWindow && !self.panelWindow.hidden) [self hidePanel];
    else [self showPanel];
}

- (NSString *)displayNameForBundleIdentifier:(NSString *)bundleIdentifier {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id controller = nil;
    if ([controllerClass respondsToSelector:sharedSelector]) {
        controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector);
    }
    id app = nil;
    SEL appSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if ([controller respondsToSelector:appSelector]) {
        app = ((id (*)(id, SEL, id))objc_msgSend)(controller, appSelector, bundleIdentifier);
    }

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
            CGSize size = CGSizeMake(38.0, 38.0);
            UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
            [image drawInRect:(CGRect){CGPointZero, size}];
            UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            UIImage *result = [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            if (result) [self.iconCache setObject:result forKey:bundleIdentifier];
            return result;
        }
    }
    if (@available(iOS 13.0, *)) return [UIImage systemImageNamed:@"app.fill"];
    return nil;
}

- (void)showPanel {
    if (![SWPreferences enabled]) return;
    [self rebuildPanel];
    self.panelWindow.hidden = NO;
}

- (void)hidePanel {
    self.panelWindow.hidden = YES;
}

- (void)rebuildPanel {
    NSArray<NSString *> *apps = [SWPreferences selectedBundleIdentifiers];
    CGRect screen = [self activeScreenBounds];
    const NSInteger columns = 3;
    const CGFloat cellSize = 52.0;
    const CGFloat padding = 12.0;
    NSInteger rows = MAX(1, (NSInteger)((apps.count + columns - 1) / columns));
    NSInteger visibleRows = MIN(rows, 4);
    CGFloat width = columns * cellSize + padding * 2.0;
    CGFloat height = visibleRows * cellSize + padding * 2.0;
    CGRect frame = CGRectMake(CGRectGetWidth(screen) - width - 12.0,
                              (CGRectGetHeight(screen) - height) / 2.0,
                              width, height);
    NSString *signature = [NSString stringWithFormat:@"%@|%.0fx%.0f",
                           [apps componentsJoinedByString:@"|"],
                           CGRectGetWidth(screen),
                           CGRectGetHeight(screen)];

    if (self.panelWindow && [self.panelSignature isEqualToString:signature]) {
        self.panelWindow.frame = frame;
        return;
    }
    self.panelSignature = signature;

    if (!self.panelWindow) {
        self.panelWindow = [self windowWithFrame:frame level:UIWindowLevelAlert + 90.0];
        if (!self.panelWindow) {
            SWFileLog(@"UI panel creation refused: no safe UIWindowScene");
            return;
        }
    } else {
        self.panelWindow.frame = frame;
    }

    UIView *root = self.panelWindow.rootViewController.view;
    [root.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    root.backgroundColor = UIColor.clearColor;
    root.layer.cornerRadius = 26.0;
    root.layer.borderWidth = 0.5;
    root.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    root.clipsToBounds = YES;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    blur.frame = root.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:blur];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectInset(root.bounds, padding, padding)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = rows > visibleRows;
    [root addSubview:scroll];

    [apps enumerateObjectsUsingBlock:^(NSString *bundleID, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSInteger row = (NSInteger)index / columns;
        NSInteger column = (NSInteger)index % columns;
        CGFloat buttonSize = 48.0;
        CGFloat x = column * cellSize + (cellSize - buttonSize) / 2.0;
        CGFloat y = row * cellSize + (cellSize - buttonSize) / 2.0;

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

- (void)appButtonTapped:(SWAppButton *)sender {
    NSString *bundleID = sender.bundleIdentifier;
    if (bundleID.length == 0) return;
    [self hidePanel];
    [self openBundleIdentifier:bundleID];
}

- (void)openBundleIdentifier:(NSString *)bundleIdentifier {
    SWFileLog(@"OPEN request %@", bundleIdentifier);
    [self prepareHostWindowForBundleIdentifier:bundleIdentifier];
    if (!self.hostWindow) {
        [self showFailureBubble:@"Could not create the SplitWindow host window."];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.sceneHost openBundleIdentifier:bundleIdentifier completion:^(UIView *hostedView, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error || !hostedView) {
            SWFileLog(@"OPEN failed %@ error=%@", bundleIdentifier, error);
            [self dismissHostWindowPreservingScene:NO];
            [self showFailureBubble:error.localizedDescription ?: @"Scene host failed"];
            return;
        }
        [self attachHostedView:hostedView bundleIdentifier:bundleIdentifier];
    }];
}

- (CGFloat)hostTitleHeight {
    return 34.0;
}

- (CGFloat)clampedHostScale:(CGFloat)scale {
    CGRect screen = [self activeScreenBounds];
    CGFloat titleHeight = [self hostTitleHeight];
    CGFloat maxWidthScale = (CGRectGetWidth(screen) - 16.0) / MAX(1.0, CGRectGetWidth(screen));
    CGFloat maxHeightScale = (CGRectGetHeight(screen) - titleHeight - 24.0) / MAX(1.0, CGRectGetHeight(screen));
    CGFloat maximum = MIN(0.95, MIN(maxWidthScale, maxHeightScale));
    maximum = MAX(0.52, maximum);
    return MAX(0.42, MIN(scale, maximum));
}

- (CGRect)hostFrameForCurrentScale {
    CGRect screen = [self activeScreenBounds];
    self.hostScale = [self clampedHostScale:self.hostScale];
    CGFloat titleHeight = [self hostTitleHeight];
    CGFloat width = floor(CGRectGetWidth(screen) * self.hostScale);
    CGFloat contentHeight = floor(CGRectGetHeight(screen) * self.hostScale);
    CGFloat height = contentHeight + titleHeight;

    CGPoint normalized = self.hostNormalizedCenter;
    if (normalized.x <= 0 || normalized.x >= 1 || normalized.y <= 0 || normalized.y >= 1) {
        normalized = CGPointMake(0.5, 0.5);
    }
    CGFloat centerX = CGRectGetMinX(screen) + CGRectGetWidth(screen) * normalized.x;
    CGFloat centerY = CGRectGetMinY(screen) + CGRectGetHeight(screen) * normalized.y;
    CGFloat x = centerX - width * 0.5;
    CGFloat y = centerY - height * 0.5;
    x = MAX(CGRectGetMinX(screen) + 4.0, MIN(x, CGRectGetMaxX(screen) - width - 4.0));
    y = MAX(CGRectGetMinY(screen) + 18.0, MIN(y, CGRectGetMaxY(screen) - height - 8.0));
    return CGRectMake(floor(x), floor(y), width, height);
}

- (void)configureBackdropGesture {
    if (!self.backdropWindow) return;
    UIView *root = self.backdropWindow.rootViewController.view;
    for (UIGestureRecognizer *recognizer in root.gestureRecognizers.copy) [root removeGestureRecognizer:recognizer];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped:)];
    tap.numberOfTapsRequired = [SWPreferences dismissRequiresDoubleTap] ? 2 : 1;
    tap.cancelsTouchesInView = YES;
    [root addGestureRecognizer:tap];
}

- (void)ensureBackdropWindow {
    CGRect screen = [self activeScreenBounds];
    if (!self.backdropWindow) {
        self.backdropWindow = [self windowWithFrame:screen level:UIWindowLevelAlert + 79.0];
        self.backdropWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    } else {
        self.backdropWindow.frame = screen;
    }
    [self configureBackdropGesture];
}

- (void)prepareHostWindowForBundleIdentifier:(NSString *)bundleIdentifier {
    [self ensureBackdropWindow];
    CGRect initialFrame = [self hostFrameForCurrentScale];
    if (!self.hostWindow) {
        self.hostWindow = [self windowWithFrame:initialFrame level:UIWindowLevelAlert + 80.0];
        if (!self.hostWindow) {
            SWFileLog(@"HOST refused host window: no safe UIWindowScene");
            return;
        }

        UIView *root = self.hostWindow.rootViewController.view;
        root.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.985];
        root.layer.cornerRadius = 18.0;
        root.clipsToBounds = YES;
        root.layer.borderWidth = 0.5;
        root.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;

        self.titleBar = [UIView new];
        self.titleBar.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.98];
        [root addSubview:self.titleBar];
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragHostWindow:)];
        [self.titleBar addGestureRecognizer:drag];

        self.hostIconView = [UIImageView new];
        self.hostIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.hostIconView.layer.cornerRadius = 5.0;
        self.hostIconView.layer.masksToBounds = YES;
        [self.titleBar addSubview:self.hostIconView];

        self.hostTitleLabel = [UILabel new];
        self.hostTitleLabel.textColor = UIColor.whiteColor;
        self.hostTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [self.titleBar addSubview:self.hostTitleLabel];

        self.sceneClipView = [UIView new];
        self.sceneClipView.backgroundColor = [UIColor colorWithWhite:0.02 alpha:1.0];
        self.sceneClipView.clipsToBounds = YES;
        [root addSubview:self.sceneClipView];

        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.loadingIndicator.hidesWhenStopped = YES;
        [self.sceneClipView addSubview:self.loadingIndicator];

        self.resizeHandle = [UIView new];
        self.resizeHandle.backgroundColor = UIColor.clearColor;
        UIImageView *resizeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]];
        resizeIcon.tag = 991;
        resizeIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.62];
        resizeIcon.contentMode = UIViewContentModeScaleAspectFit;
        [self.resizeHandle addSubview:resizeIcon];
        UIPanGestureRecognizer *resize = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeHostWindow:)];
        [self.resizeHandle addGestureRecognizer:resize];
        [root addSubview:self.resizeHandle];
    }

    [self.hostedView removeFromSuperview];
    self.hostedView = nil;
    self.hostIconView.image = [self iconForBundleIdentifier:bundleIdentifier];
    self.hostTitleLabel.text = [self displayNameForBundleIdentifier:bundleIdentifier];
    [self.loadingIndicator startAnimating];
    [self layoutHostWindowAnimated:NO];
    self.backdropWindow.hidden = NO;
    self.hostWindow.hidden = NO;
    SWFileLog(@"HOST shell presented %@ frame=%@ scale=%.2f", bundleIdentifier, NSStringFromCGRect(self.hostWindow.frame), self.hostScale);
}

- (void)attachHostedView:(UIView *)hostedView bundleIdentifier:(NSString *)bundleIdentifier {
    if (!self.hostWindow || !self.sceneClipView) return;
    [self.hostedView removeFromSuperview];
    self.hostedView = hostedView;
    hostedView.userInteractionEnabled = YES;
    hostedView.layer.anchorPoint = CGPointZero;
    hostedView.layer.position = CGPointZero;
    [self.sceneClipView insertSubview:hostedView atIndex:0];
    [self layoutHostWindowAnimated:NO];

    CGRect screen = [self activeScreenBounds];
    UIInterfaceOrientation orientation = [self activeInterfaceOrientation];
    [self.sceneHost updateSceneForHostBounds:screen interfaceOrientation:orientation];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.hostedView == hostedView) {
            [self.sceneHost updateSceneForHostBounds:[self activeScreenBounds]
                                interfaceOrientation:[self activeInterfaceOrientation]];
            [self.loadingIndicator stopAnimating];
        }
    });
    SWFileLog(@"HOST attached %@ frame=%@", bundleIdentifier, NSStringFromCGRect(self.hostWindow.frame));
}

- (void)layoutHostWindowAnimated:(BOOL)animated {
    if (!self.hostWindow) return;
    CGRect screen = [self activeScreenBounds];
    CGRect frame = [self hostFrameForCurrentScale];
    CGFloat titleHeight = [self hostTitleHeight];
    CGFloat contentWidth = CGRectGetWidth(frame);
    CGFloat contentHeight = CGRectGetHeight(frame) - titleHeight;
    void (^layoutBlock)(void) = ^{
        self.hostWindow.frame = frame;
        self.titleBar.frame = CGRectMake(0, 0, contentWidth, titleHeight);
        self.hostIconView.frame = CGRectMake(10, 6, 22, 22);
        CGFloat titleX = self.hostIconView.image ? 39.0 : 13.0;
        self.hostTitleLabel.frame = CGRectMake(titleX, 0, MAX(20.0, contentWidth - titleX - 12.0), titleHeight);
        self.sceneClipView.frame = CGRectMake(0, titleHeight, contentWidth, contentHeight);
        self.loadingIndicator.center = CGPointMake(contentWidth * 0.5, contentHeight * 0.5);
        self.resizeHandle.frame = CGRectMake(MAX(0.0, contentWidth - 34.0), MAX(titleHeight, CGRectGetHeight(frame) - 34.0), 34.0, 34.0);
        UIImageView *resizeIcon = [self.resizeHandle viewWithTag:991];
        resizeIcon.frame = CGRectMake(9, 9, 16, 16);
        if (self.hostedView) {
            self.hostedView.bounds = CGRectMake(0, 0, CGRectGetWidth(screen), CGRectGetHeight(screen));
            self.hostedView.layer.anchorPoint = CGPointZero;
            self.hostedView.layer.position = CGPointZero;
            self.hostedView.transform = CGAffineTransformMakeScale(self.hostScale, self.hostScale);
        }
    };
    if (animated) [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:layoutBlock completion:nil];
    else layoutBlock();
}

- (void)backdropTapped:(__unused UITapGestureRecognizer *)gesture {
    [self dismissHostWindowPreservingScene:YES];
}

- (void)dragHostWindow:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGRect frame = window.frame;
    frame.origin.x += translation.x;
    frame.origin.y += translation.y;
    CGRect screen = [self activeScreenBounds];
    frame.origin.x = MAX(CGRectGetMinX(screen) + 4.0, MIN(frame.origin.x, CGRectGetMaxX(screen) - CGRectGetWidth(frame) - 4.0));
    frame.origin.y = MAX(CGRectGetMinY(screen) + 18.0, MIN(frame.origin.y, CGRectGetMaxY(screen) - CGRectGetHeight(frame) - 8.0));
    window.frame = frame;
    self.hostNormalizedCenter = CGPointMake(CGRectGetMidX(frame) / MAX(1.0, CGRectGetWidth(screen)),
                                            CGRectGetMidY(frame) / MAX(1.0, CGRectGetHeight(screen)));
    [gesture setTranslation:CGPointZero inView:window];
}

- (void)resizeHostWindow:(UIPanGestureRecognizer *)gesture {
    if (!self.hostWindow) return;
    CGPoint translation = [gesture translationInView:self.hostWindow];
    CGRect screen = [self activeScreenBounds];
    CGFloat denominator = MAX(180.0, MIN(CGRectGetWidth(screen), CGRectGetHeight(screen)));
    CGFloat delta = (translation.x + translation.y) * 0.5 / denominator;
    if (fabs(delta) > 0.0001) {
        self.hostScale = [self clampedHostScale:self.hostScale + delta];
        [self layoutHostWindowAnimated:NO];
        [gesture setTranslation:CGPointZero inView:self.hostWindow];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [SWPreferences setWindowScale:self.hostScale];
        SWFileLog(@"HOST resize scale=%.3f frame=%@", self.hostScale, NSStringFromCGRect(self.hostWindow.frame));
    }
}

- (void)dismissHostWindowPreservingScene:(BOOL)preserveScene {
    self.hostWindow.hidden = YES;
    self.backdropWindow.hidden = YES;
    [self.loadingIndicator stopAnimating];
    [self.hostedView removeFromSuperview];
    self.hostedView = nil;
    if (preserveScene) [self.sceneHost dismissPresentationPreservingScene];
    else [self.sceneHost close];
}

- (void)closeHostWindow {
    [self dismissHostWindowPreservingScene:NO];
    self.hostWindow.rootViewController = nil;
    self.hostWindow = nil;
    self.backdropWindow.rootViewController = nil;
    self.backdropWindow = nil;
    self.titleBar = nil;
    self.sceneClipView = nil;
    self.resizeHandle = nil;
    self.loadingIndicator = nil;
    self.hostTitleLabel = nil;
    self.hostIconView = nil;
}

- (void)showFailureBubble:(NSString *)message {
    CGRect screen = [self activeScreenBounds];
    UIWindow *window = [self windowWithFrame:CGRectMake(24, 80, CGRectGetWidth(screen) - 48, 58) level:UIWindowLevelAlert + 120.0];
    if (!window) return;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(window.bounds, 12, 8)];
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    window.rootViewController.view.backgroundColor = [UIColor colorWithRed:0.45 green:0.08 blue:0.08 alpha:0.96];
    window.rootViewController.view.layer.cornerRadius = 14;
    [window.rootViewController.view addSubview:label];
    window.hidden = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        window.hidden = YES;
    });
}

@end
