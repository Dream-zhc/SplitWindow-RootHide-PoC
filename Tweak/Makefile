ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitWindow

SplitWindow_FILES = Loader.m
SplitWindow_FRAMEWORKS = CoreFoundation
SplitWindow_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
