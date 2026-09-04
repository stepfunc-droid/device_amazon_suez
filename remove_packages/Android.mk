LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := SuezRemovePackages
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := APPS
LOCAL_OVERRIDES_PACKAGES := \
    AudioFX \
    Backgrounds \
    Contacts \
    DeskClock \
    Email \
    Eleven \
    Gallery2 \
    LatinIME \
    LineageSetupWizard \
    Recorder \
    Telecom \
    TeleService \
    Traceur \
    Updater
LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_CERTIFICATE := PRESIGNED
include $(BUILD_PREBUILT)
