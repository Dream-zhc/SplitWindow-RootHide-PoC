ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitWindow

SplitWindow_FILES = Loader.c
SplitWindow_FRAMEWORKS = CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
