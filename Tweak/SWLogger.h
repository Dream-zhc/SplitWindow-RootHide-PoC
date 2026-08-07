#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT NSString * const SWLogFilePath;
FOUNDATION_EXPORT void SWFileLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
