#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const SWPrefsDomain = @"com.dream.splitwindow";
static NSString * const SWActivationNotification = @"com.dream.splitwindow/activationRequested";
static NSString * const SWPreferencesNotification = @"com.dream.splitwindow/preferencesChanged";

@interface SWRootListController : UITableViewController
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *floatingSwitch;
@end

@implementation SWRootListController

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SplitWindow";

    self.enabledSwitch = [UISwitch new];
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    self.floatingSwitch = [UISwitch new];
    [self.floatingSwitch addTarget:self action:@selector(floatingChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadValues];
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    CFStringRef domain = (__bridge CFStringRef)SWPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    if (!value) return defaultValue;

    BOOL result = defaultValue;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int number = 0;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &number)) result = number != 0;
    }
    CFRelease(value);
    return result;
}

- (void)setBool:(BOOL)value forKey:(NSString *)key notification:(NSString *)notification {
    CFStringRef domain = (__bridge CFStringRef)SWPrefsDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             value ? kCFBooleanTrue : kCFBooleanFalse,
                             domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)notification,
                                         NULL,
                                         NULL,
                                         YES);
}

- (void)reloadValues {
    self.enabledSwitch.on = [self boolForKey:@"EnabledV040" defaultValue:NO];
    self.floatingSwitch.on = [self boolForKey:@"ShowFloatingButton" defaultValue:YES];
}

- (void)enabledChanged:(UISwitch *)sender {
    [self setBool:sender.isOn forKey:@"EnabledV040" notification:SWActivationNotification];
}

- (void)floatingChanged:(UISwitch *)sender {
    [self setBool:sender.isOn forKey:@"ShowFloatingButton" notification:SWPreferencesNotification];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"SplitWindow" : @"App";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return @"安装或 Respring 后保持安全待机。只有手动开启后才加载小窗功能模块。";
    }
    return @"先选择 Calculator / Notes 做 Scene Hosting 验证，再测试第三方 App。";
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title toggle:(UISwitch *)toggle {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0 && indexPath.row == 0) {
        return [self switchCellWithTitle:@"启用" toggle:self.enabledSwitch];
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return [self switchCellWithTitle:@"显示悬浮按钮" toggle:self.floatingSwitch];
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = @"选择小窗 App";
    cell.detailTextLabel.text = @"选择要出现在侧边面板中的应用";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || indexPath.row != 0) return;

    Class appListClass = NSClassFromString(@"SWAppListController");
    if (!appListClass) return;
    UIViewController *controller = [[appListClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
