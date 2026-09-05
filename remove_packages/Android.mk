LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := SuezRemovePackages
LOCAL_MODULE_TAGS := optional

# BUILD_PHONY_PACKAGE has no source file. Record overrides explicitly so the
# product build filters these packages out without trying to build a dummy APK.
PACKAGES.$(LOCAL_MODULE).OVERRIDES := \
    AudioFX \
    Backgrounds \
    Contacts \
    DeskClock \
    Email \
    Eleven \
    Gallery2 \
    LineageSetupWizard \
    Recorder \
    Telecom \
    TeleService \
    Traceur \
    Updater

include $(BUILD_PHONY_PACKAGE)
