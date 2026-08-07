ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SplitWindowPrefs

SplitWindowPrefs_FILES = SWRootListController.m SWAppListController.m
SplitWindowPrefs_FRAMEWORKS = Foundation UIKit
SplitWindowPrefs_INSTALL_PATH = /Library/PreferenceBundles
SplitWindowPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/bundle.mk
