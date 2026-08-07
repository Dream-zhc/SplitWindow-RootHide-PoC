#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

static const CFStringRef SWPreferencesDomain = CFSTR("com.dream.splitwindow");
static const CFStringRef SWActivationNotification = CFSTR("com.dream.splitwindow/activationRequested");
static const CFStringRef SWPreferencesNotification = CFSTR("com.dream.splitwindow/preferencesChanged");

typedef void (*SWFeatureFunction)(void);

static void *SWFeatureHandle = NULL;
static SWFeatureFunction SWFeatureStartFunction = NULL;
static SWFeatureFunction SWFeatureReloadFunction = NULL;

static void SWLoaderInitialize(void);

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
    if (SWFeatureHandle && SWFeatureStartFunction && SWFeatureReloadFunction) return true;

    char path[8192];
    if (!SWFeaturePath(path, sizeof(path))) return false;

    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) return false;

    SWFeatureFunction start = (SWFeatureFunction)dlsym(handle, "SWFeatureStart");
    SWFeatureFunction reload = (SWFeatureFunction)dlsym(handle, "SWFeatureReload");
    if (!start || !reload) {
        dlclose(handle);
        return false;
    }

    SWFeatureHandle = handle;
    SWFeatureStartFunction = start;
    SWFeatureReloadFunction = reload;
    return true;
}

static void SWHandleActivationOnMain(void *context) {
    (void)context;
    if (!SWPreferenceEnabled()) {
        if (SWFeatureReloadFunction) SWFeatureReloadFunction();
        return;
    }

    if (!SWLoadFeatureIfNeeded()) return;
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
