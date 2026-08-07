#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface SWRootListController : PSListController
@end

@implementation SWRootListController

- (NSArray *)specifiers {
    static void *kSpecifiersKey = &kSpecifiersKey;
    NSArray *specifiers = objc_getAssociatedObject(self, kSpecifiersKey);
    if (!specifiers) {
        specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        objc_setAssociatedObject(self, kSpecifiersKey, specifiers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return specifiers;
}

@end
