ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = SplitWindowFeature

SplitWindowFeature_FILES = SWFeatureEntry.m ../Tweak/SWLogger.m ../Tweak/SWPreferences.m ../Tweak/SWSceneHost.m ../Tweak/SWOverlayController.m
SplitWindowFeature_FRAMEWORKS = Foundation UIKit QuartzCore
SplitWindowFeature_INSTALL_PATH = /Library/SplitWindow
SplitWindowFeature_CFLAGS = -fobjc-arc -I../Tweak -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/library.mk
