export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:16.0
export THEOS_PACKAGE_SCHEME = roothide
export DEB_ARCH = iphoneos-arm64

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Feature Tweak Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
