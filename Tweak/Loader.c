#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static const CFStringRef SWPreferencesDomain = CFSTR("com.dream.splitwindow");
static const CFStringRef SWActivationNotification = CFSTR("com.dream.splitwindow/activationRequested");
static const CFStringRef SWPreferencesNotification = CFSTR("com.dream.splitwindow/preferencesChanged");

typedef void (*SWFeatureFunction)(void);

static void *SWFeatureHandle = NULL;
static SWFeatureFunction SWFeatureStartFunction = NULL;
static SWFeatureFunction SWFeatureReloadFunction = NULL;

static void SWLoaderInitialize(void);

static void SWLoaderLog(const char *format, ...) {
    if (!format) return;

    mkdir("/var/mobile/SplitWindow", 0755);
    mkdir("/var/mobile/SplitWindow/logs", 0755);

    FILE *file = fopen("/var/mobile/SplitWindow/logs/loader.log", "a");
    if (!file) return;

    va_list args;
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    fputc('\n', file);
    fclose(file);
}

static bool SWPreferenceEnabled(void) {
    CFPreferencesAppSynchronize(SWPreferencesDomain);
    // v0.4 deliberately uses a new key. Old releases could leave Enabled=true
    // behind after uninstall; that stale value must never activate this loader.
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("EnabledV040"), SWPreferencesDomain);
    bool enabled = false;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    }
    if (value) CFRelease(value);
    return enabled;
}

static bool SWFeaturePath(char *buffer, size_t bufferSize) {
    if (!buffer || bufferSize == 0) return false;

    Dl_info info = {0};
    if (dladdr((const void *)&SWLoaderInitialize, &info) == 0 || !info.dli_fname) return false;

    const char *imagePath = info.dli_fname;
    const char *marker = strstr(imagePath, "/Library/MobileSubstrate/DynamicLibraries/");
    if (!marker) marker = strstr(imagePath, "/Library/TweakInject/");
    if (!marker) return false;

    size_t prefixLength = (size_t)(marker - imagePath);
    if (prefixLength > 4096) return false;

    int written = snprintf(buffer,
                           bufferSize,
                           "%.*s/Library/SplitWindow/SplitWindowFeature.dylib",
                           (int)prefixLength,
                           imagePath);
    return written > 0 && (size_t)written < bufferSize;
}

static bool SWLoadFeatureIfNeeded(void) {
    if (SWFeatureHandle && SWFeatureStartFunction && SWFeatureReloadFunction) {
        SWLoaderLog("FEATURE already loaded");
        return true;
    }

    char path[8192];
    if (!SWFeaturePath(path, sizeof(path))) {
        SWLoaderLog("FEATURE path resolution failed");
        return false;
    }

    SWLoaderLog("FEATURE path=%s", path);

    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *error = dlerror();
        SWLoaderLog("FEATURE dlopen failed: %s", error ? error : "unknown");
        return false;
    }

    SWFeatureFunction start = (SWFeatureFunction)dlsym(handle, "SWFeatureStart");
    SWFeatureFunction reload = (SWFeatureFunction)dlsym(handle, "SWFeatureReload");
    if (!start || !reload) {
        SWLoaderLog("FEATURE missing entry points start=%p reload=%p", start, reload);
        dlclose(handle);
        return false;
    }

    SWFeatureHandle = handle;
    SWFeatureStartFunction = start;
    SWFeatureReloadFunction = reload;
    SWLoaderLog("FEATURE loaded successfully");
    return true;
}

static void SWHandleActivationOnMain(void *context) {
    (void)context;
    bool enabled = SWPreferenceEnabled();
    SWLoaderLog("ACTIVATION enabled=%d", enabled ? 1 : 0);
    if (!enabled) {
        if (SWFeatureReloadFunction) SWFeatureReloadFunction();
        return;
    }

    if (!SWLoadFeatureIfNeeded()) {
        SWLoaderLog("ACTIVATION feature load failed");
        return;
    }
    SWLoaderLog("ACTIVATION invoking feature start");
    SWFeatureStartFunction();
}

static void SWHandlePreferencesOnMain(void *context) {
    (void)context;
    if (SWFeatureReloadFunction) SWFeatureReloadFunction();
}

static void SWActivationChanged(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async_f(dispatch_get_main_queue(), NULL, SWHandleActivationOnMain);
}

static void SWPreferencesChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async_f(dispatch_get_main_queue(), NULL, SWHandlePreferencesOnMain);
}

__attribute__((constructor))
static void SWLoaderInitialize(void) {
    // Deliberately minimal. Pure C: no Objective-C runtime, UIKit, file I/O,
    // UIWindow creation, FrontBoard lookup, or feature dylib loading here.
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    SWActivationChanged,
                                    SWActivationNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    SWPreferencesChanged,
                                    SWPreferencesNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
