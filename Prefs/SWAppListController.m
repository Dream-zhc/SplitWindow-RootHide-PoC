#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>

static NSString * const SWDomain = @"com.dream.splitwindow";
static NSString * const SWNotification = @"com.dream.splitwindow/preferencesChanged";

@interface SWAppEntry : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) UIImage *icon;
@end
@implementation SWAppEntry
@end

@interface SWAppListController : UITableViewController
@property (nonatomic, strong) NSArray<SWAppEntry *> *apps;
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;
@end

@implementation SWAppListController

- (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return nil;
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) return nil;
    UIImage *image = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(UIImage.class,
                                                                             selector,
                                                                             bundleIdentifier,
                                                                             10,
                                                                             UIScreen.mainScreen.scale);
    if (![image isKindOfClass:[UIImage class]]) return nil;
    CGSize size = CGSizeMake(34.0, 34.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
    [image drawInRect:(CGRect){CGPointZero, size}];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择小窗 App";
    self.tableView.allowsMultipleSelection = YES;
    [self loadSelectedApps];
    [self loadApplications];
}

- (void)loadSelectedApps {
    CFStringRef domain = (__bridge CFStringRef)SWDomain;
    CFPreferencesAppSynchronize(domain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SelectedApps"), domain));
    if ([value isKindOfClass:[NSArray class]]) self.selected = [NSMutableSet setWithArray:value];
    else self.selected = [NSMutableSet setWithArray:@[@"com.apple.calculator", @"com.apple.mobilenotes"]];
}

- (void)loadApplications {
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
    id workspace = nil;
    if ([workspaceClass respondsToSelector:defaultWorkspaceSel]) {
        workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspaceSel);
    }

    NSArray *proxies = nil;
    SEL allAppsSel = NSSelectorFromString(@"allApplications");
    if ([workspace respondsToSelector:allAppsSel]) {
        proxies = ((id (*)(id, SEL))objc_msgSend)(workspace, allAppsSel);
    }

    NSMutableArray<SWAppEntry *> *entries = [NSMutableArray array];
    for (id proxy in proxies) {
        NSString *bundleID = nil;
        NSString *name = nil;
        NSString *type = nil;
        BOOL placeholder = NO;
        BOOL launchProhibited = NO;
        @try {
            bundleID = [proxy valueForKey:@"bundleIdentifier"];
            name = [proxy valueForKey:@"localizedName"] ?: [proxy valueForKey:@"localizedShortName"];
            type = [proxy valueForKey:@"applicationType"];
            placeholder = [[proxy valueForKey:@"placeholder"] boolValue];
            launchProhibited = [[proxy valueForKey:@"launchProhibited"] boolValue];
        } @catch (__unused NSException *exception) {}

        if (bundleID.length == 0 || name.length == 0 || placeholder || launchProhibited) continue;
        if ([bundleID isEqualToString:@"com.apple.springboard"]) continue;
        if ([type isKindOfClass:[NSString class]] && !([type isEqualToString:@"User"] || [type isEqualToString:@"System"])) continue;

        SWAppEntry *entry = [SWAppEntry new];
        entry.bundleIdentifier = bundleID;
        entry.displayName = name;
        entry.icon = [self iconForBundleIdentifier:bundleID];
        [entries addObject:entry];
    }

    [entries sortUsingComparator:^NSComparisonResult(SWAppEntry *a, SWAppEntry *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    self.apps = entries.copy;
    [self.tableView reloadData];
}

- (void)saveSelection {
    NSArray *apps = [[self.selected allObjects] sortedArrayUsingSelector:@selector(compare:)];
    CFStringRef domain = (__bridge CFStringRef)SWDomain;
    CFPreferencesSetAppValue(CFSTR("SelectedApps"), (__bridge CFPropertyListRef)apps, domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)SWNotification,
                                         NULL, NULL, YES);
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"App";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];

    SWAppEntry *entry = self.apps[indexPath.row];
    cell.textLabel.text = entry.displayName;
    cell.detailTextLabel.text = entry.bundleIdentifier;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = entry.icon;
    cell.imageView.layer.cornerRadius = 9.0;
    cell.imageView.layer.masksToBounds = YES;
    cell.accessoryType = [self.selected containsObject:entry.bundleIdentifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SWAppEntry *entry = self.apps[indexPath.row];
    if ([self.selected containsObject:entry.bundleIdentifier]) [self.selected removeObject:entry.bundleIdentifier];
    else [self.selected addObject:entry.bundleIdentifier];
    [self saveSelection];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

@end
