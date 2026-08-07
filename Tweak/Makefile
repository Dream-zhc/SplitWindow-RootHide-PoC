include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SplitWindow

SplitWindow_FILES = Tweak.xm SWLogger.m SWPreferences.m SWSceneHost.m SWOverlayController.m
SplitWindow_FRAMEWORKS = Foundation UIKit QuartzCore
SplitWindow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/tweak.mk
