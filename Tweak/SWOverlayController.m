#import "SWOverlayController.h"
#import "SWPreferences.h"
#import "SWSceneHost.h"
#import "SWLogger.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

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
@property (nonatomic, strong) UIWindow *hostWindow;
@property (nonatomic, strong) UIView *sceneClipView;
@property (nonatomic, strong) SWSceneHost *sceneHost;
@property (nonatomic, strong) UILabel *hostTitleLabel;
@property (nonatomic, strong) UIImageView *hostIconView;
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
    CGRect screen = UIScreen.mainScreen.bounds;
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
    CGRect screen = UIScreen.mainScreen.bounds;
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
        CGRect screen = UIScreen.mainScreen.bounds;
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
            return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
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
    CGRect screen = UIScreen.mainScreen.bounds;
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
    [self closeHostWindow];
    SWFileLog(@"OPEN request %@", bundleIdentifier);

    __weak typeof(self) weakSelf = self;
    [self.sceneHost openBundleIdentifier:bundleIdentifier completion:^(UIView *hostedView, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error || !hostedView) {
            SWFileLog(@"OPEN failed %@ error=%@", bundleIdentifier, error);
            [self showFailureBubble:error.localizedDescription ?: @"Scene host failed"];
            return;
        }
        [self presentHostedView:hostedView bundleIdentifier:bundleIdentifier];
    }];
}

- (void)presentHostedView:(UIView *)hostedView bundleIdentifier:(NSString *)bundleIdentifier {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat scale = 0.72;
    CGFloat titleHeight = 36.0;
    CGFloat contentWidth = floor(CGRectGetWidth(screen) * scale);
    CGFloat contentHeight = floor(CGRectGetHeight(screen) * scale);
    CGFloat totalHeight = contentHeight + titleHeight;
    CGFloat x = floor((CGRectGetWidth(screen) - contentWidth) / 2.0);
    CGFloat y = floor(MAX(40.0, (CGRectGetHeight(screen) - totalHeight) / 2.0));

    self.hostWindow = [self windowWithFrame:CGRectMake(x, y, contentWidth, totalHeight) level:UIWindowLevelAlert + 80.0];
    if (!self.hostWindow) {
        SWFileLog(@"HOST-5 refused host window: no safe UIWindowScene");
        [self.sceneHost close];
        return;
    }
    UIView *root = self.hostWindow.rootViewController.view;
    root.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.98];
    root.layer.cornerRadius = 18.0;
    root.clipsToBounds = YES;
    root.layer.borderWidth = 0.5;
    root.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;

    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, titleHeight)];
    titleBar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [root addSubview:titleBar];

    self.hostTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, contentWidth - 58, titleHeight)];
    UIImage *icon = [self iconForBundleIdentifier:bundleIdentifier];
    CGFloat titleX = 14.0;
    if (icon) {
        self.hostIconView = [[UIImageView alloc] initWithImage:icon];
        self.hostIconView.frame = CGRectMake(10, 7, 22, 22);
        self.hostIconView.contentMode = UIViewContentModeScaleAspectFit;
        self.hostIconView.layer.cornerRadius = 5.0;
        self.hostIconView.layer.masksToBounds = YES;
        [titleBar addSubview:self.hostIconView];
        titleX = 39.0;
    }
    self.hostTitleLabel.frame = CGRectMake(titleX, 0, contentWidth - titleX - 44, titleHeight);
    self.hostTitleLabel.text = [self displayNameForBundleIdentifier:bundleIdentifier];
    self.hostTitleLabel.textColor = UIColor.whiteColor;
    self.hostTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [titleBar addSubview:self.hostTitleLabel];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(contentWidth - 42, 0, 42, titleHeight);
    close.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *)) [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    else [close setTitle:@"×" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeHostWindow) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:close];

    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragHostWindow:)];
    [titleBar addGestureRecognizer:drag];

    self.sceneClipView = [[UIView alloc] initWithFrame:CGRectMake(0, titleHeight, contentWidth, contentHeight)];
    self.sceneClipView.backgroundColor = UIColor.blackColor;
    self.sceneClipView.clipsToBounds = YES;
    [root addSubview:self.sceneClipView];

    hostedView.bounds = screen;
    hostedView.layer.anchorPoint = CGPointZero;
    hostedView.layer.position = CGPointZero;
    hostedView.transform = CGAffineTransformMakeScale(scale, scale);
    hostedView.userInteractionEnabled = YES;
    [self.sceneClipView addSubview:hostedView];

    self.hostWindow.hidden = NO;
    SWFileLog(@"HOST-5 window presented %@ frame=%@", bundleIdentifier, NSStringFromCGRect(self.hostWindow.frame));
}

- (void)dragHostWindow:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGRect frame = window.frame;
    frame.origin.x += translation.x;
    frame.origin.y += translation.y;
    CGRect screen = UIScreen.mainScreen.bounds;
    frame.origin.x = MAX(0.0, MIN(frame.origin.x, CGRectGetWidth(screen) - CGRectGetWidth(frame)));
    frame.origin.y = MAX(24.0, MIN(frame.origin.y, CGRectGetHeight(screen) - CGRectGetHeight(frame) - 8.0));
    window.frame = frame;
    [gesture setTranslation:CGPointZero inView:window];
}

- (void)closeHostWindow {
    if (self.hostWindow) {
        self.hostWindow.hidden = YES;
        self.hostWindow.rootViewController = nil;
        self.hostWindow = nil;
        self.sceneClipView = nil;
        self.hostTitleLabel = nil;
        self.hostIconView = nil;
    }
    [self.sceneHost close];
}

- (void)showFailureBubble:(NSString *)message {
    CGRect screen = UIScreen.mainScreen.bounds;
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
