#import "SWLogger.h"

NSString * const SWLogFilePath = @"/var/mobile/SplitWindow/logs/splitwindow.log";

static NSString *SWTimestamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:[NSDate date]];
    }
}

static void SWRotateLogIfNeeded(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:SWLogFilePath error:nil];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    if (size < 512 * 1024) return;

    NSString *backup = [SWLogFilePath stringByAppendingString:@".1"];
    [fm removeItemAtPath:backup error:nil];
    [fm moveItemAtPath:SWLogFilePath toPath:backup error:nil];
}

void SWFileLog(NSString *format, ...) {
    if (format.length == 0) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", SWTimestamp(), message];
    NSLog(@"[SplitWindow] %@", message);

    @synchronized ([NSFileManager class]) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [SWLogFilePath stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        SWRotateLogIfNeeded();

        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:SWLogFilePath]) {
            [data writeToFile:SWLogFilePath atomically:YES];
            return;
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:SWLogFilePath];
        if (!handle) return;
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (__unused NSException *exception) {
        }
        [handle closeFile];
    }
}
