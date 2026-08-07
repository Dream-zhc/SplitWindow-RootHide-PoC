ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitWindow

SplitWindow_FILES = Tweak.xm SWLogger.m SWPreferences.m SWSceneHost.m SWOverlayController.m
SplitWindow_FRAMEWORKS = Foundation UIKit QuartzCore
SplitWindow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/tweak.mk
