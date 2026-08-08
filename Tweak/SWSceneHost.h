#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SWSceneHostCompletion)(UIView * _Nullable hostedView, NSError * _Nullable error);

@interface SWSceneHost : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *bundleIdentifier;
@property (nonatomic, strong, readonly, nullable) id scene;
@property (nonatomic, strong, readonly, nullable) id presenter;

- (void)openBundleIdentifier:(NSString *)bundleIdentifier
           foregroundHandoff:(BOOL)foregroundHandoff
                  completion:(SWSceneHostCompletion)completion;
- (void)updateSceneForHostBounds:(CGRect)hostBounds interfaceOrientation:(UIInterfaceOrientation)orientation;
- (void)dismissPresentationPreservingScene;
- (void)relinquishPresentationForSystemForeground;
- (void)close;
@end

NS_ASSUME_NONNULL_END
