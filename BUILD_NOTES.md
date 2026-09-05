# Suez LineageOS 16 build notes

This file records the build/rebuild pitfalls found while working on the Amazon Fire HD 10 (2017), codename `suez`, so the next build does not have to rediscover them.

## Build target

- Device: Amazon Fire HD 10 (2017), `suez`
- SoC: MediaTek MT8173
- GPU: PowerVR GX6250
- ROM: LineageOS 16.0 / Android 9
- GApps, if needed: OpenGApps **ARM64 / Android 9.0 / pico**

## Normal rebuild

From the LineageOS source root:

```bash
cd ~/lineage-16.0

git -C device/amazon/suez pull

source build/envsetup.sh
lunch lineage_suez-userdebug
mka bacon
```

If packages were added/removed from the system image, run an install clean first so stale APKs do not remain in `out/`:

```bash
m installclean
mka bacon
```

A full `make clean` is normally unnecessary.

## Device patches

Device-specific source patches live under:

```text
device/amazon/suez/patches/
```

and are applied by:

```bash
device/amazon/suez/patches/apply.sh
```

`apply.sh` changes into each target repository before running `git apply`. For example, patches under:

```text
patches/frameworks/base/
```

are applied with `frameworks/base` as the current working directory.

### Important: do not blindly re-run patches

`git apply` is not idempotent. If the source tree already has the patches applied, running `apply.sh` again will fail or create unnecessary recovery work.

Before applying patches to an existing source tree, check the relevant repository first:

```bash
git -C frameworks/base status --short
```

For a fresh/reset source tree, apply the patches once. For an already-patched tree, simply keep building unless the patch files themselves changed.

## PowerVR hardware bitmap fixes

There are two separate and already-tested framework patches. Keep them separate unless there is a real reason to change them:

```text
patches/frameworks/base/0001-Hardware-bitmaps-support-workaround.patch
patches/frameworks/base/0005-SystemUI-avoid-hardware-bitmaps-for-navigation-keys.patch
```

### `0001-Hardware-bitmaps-support-workaround.patch`

This is the existing MTK/PowerVR workaround for broken/incomplete Android hardware-bitmap handling.

### `0005-SystemUI-avoid-hardware-bitmaps-for-navigation-keys.patch`

This fixes corrupted Back/Home/Recents icons in SystemUI.

The failure was very specific:

- only the three navigation icons were corrupted;
- the navigation-bar background was fine;
- the corruption was visible in screenshots;
- disabling HW overlays did not fix it;
- hiding the navigation bar removed the corruption.

The culprit is `ShadowKeyDrawable`, which rendered an ARGB bitmap and then converted it to `Bitmap.Config.HARDWARE`:

```java
bitmap = bitmap.copy(Bitmap.Config.HARDWARE, false);
```

On this MT8173/PowerVR userspace stack that conversion can corrupt the icon. Patch `0005` removes that conversion and keeps the cached bitmap in ARGB_8888.

This fix has been verified on-device. Do not remove or casually fold/rewrite these patches during unrelated cleanup.

## Removing unnecessary system apps

The system partition is small enough that OpenGApps Pico can fail with:

```text
insufficient storage space available in system partition
```

The device tree therefore removes a number of replaceable/unnecessary Lineage/AOSP apps through:

```text
remove_packages/Android.mk
```

### Correct removal mechanism

Do **not** implement the removal helper as an APK prebuilt with `BUILD_PREBUILT` and no source file. That fails during ckati with:

```text
SuezRemovePackages: No source files specified
build/make/core/prebuilt_internal.mk:35: error: done.
```

The correct approach is a phony module and explicit package override list:

```make
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := SuezRemovePackages
LOCAL_MODULE_TAGS := optional

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
```

and `device.mk` includes:

```make
PRODUCT_PACKAGES += \
    SuezRemovePackages
```

`LOCAL_OVERRIDES_PACKAGES` is not reliable for a phony package here, so the override is assigned directly through `PACKAGES.$(LOCAL_MODULE).OVERRIDES`.

### Keep LatinIME

Do **not** remove `LatinIME` unless another keyboard is preinstalled.

OpenGApps Pico does not provide Gboard. A clean install with no input method makes initial Google account login impractical because there is no keyboard for entering the account/password.

After building, verify that `LatinIME` is still present:

```bash
find out/target/product/suez/system -iname '*LatinIME*'
```

and verify removed apps are absent, for example:

```bash
find out/target/product/suez/system \
    \( -iname '*AudioFX*' \
    -o -iname '*Backgrounds*' \
    -o -iname '*Gallery2*' \
    -o -iname '*Eleven*' \
    -o -iname '*Updater*' \)
```

## WebView is large, but do not delete it blindly

The current build includes:

```make
PRODUCT_PACKAGES += \
    bromite-webview
```

The WebView APK is very large (roughly 233 MB in one build), but Android apps rely on having a functioning WebView provider. Do not remove it just to save space unless it is being replaced by another valid provider.

## OpenGApps: do not integrate the full source tree just for Pico

An attempted OpenGApps AOSP-source integration required syncing:

```text
vendor/opengapps/build
vendor/opengapps/sources/all
vendor/opengapps/sources/arm
vendor/opengapps/sources/arm64
```

plus Git LFS objects. That is several GB of source/assets just to package Pico and is unnecessary for this device workflow.

The OpenGApps source-tree integration was removed from this device tree.

If those repositories were previously synced locally, they can be removed with:

```bash
cd ~/lineage-16.0
rm -f .repo/local_manifests/opengapps.xml
rm -rf vendor/opengapps
rm -rf .repo/projects/vendor/opengapps
```

If desired, inspect `.repo/project-objects` before deleting any matching OpenGApps objects. Avoid broad `find ... -exec rm -rf` commands unless the paths have been checked first.

## Recommended flashing sequence

For an update of the same LineageOS 16 build family, a normal TWRP sideload is sufficient. There is no need to wipe `/system` merely because system apps were removed from the new build.

1. Sideload the ROM:

```bash
adb sideload lineage-16.0-*-suez.zip
```

2. Without booting Android, sideload OpenGApps Pico:

```bash
adb sideload open_gapps-arm64-9.0-pico-20220215.zip
```

3. Optionally wipe Dalvik/cache in TWRP.
4. Reboot System.

For a normal update of the same ROM, `/data` does not need to be wiped either.

A clean flash should only be used when changing ROM families/Android versions or when troubleshooting persistent state-related problems.

## Useful size checks

Check the generated system tree:

```bash
du -sh out/target/product/suez/system
```

Find the largest system directories/APKs:

```bash
du -h -d 2 \
    out/target/product/suez/system/app \
    out/target/product/suez/system/priv-app \
    2>/dev/null | sort -h | tail -30
```

Also remember that `du` of the unpacked output tree is not exactly the same thing as free space inside the final ext4 system image; filesystem metadata and image-generation constraints still matter.

## General rule for future changes

Avoid unrelated cleanup while fixing a known problem. In particular:

- do not reorder/merge already-working patches just for tidiness;
- do not modify unrelated device configuration while solving another issue;
- inspect `git diff` before pushing;
- when changing the list of installed system packages, use `m installclean` before the next build;
- when a build stops during ckati/product configuration, fix the makefile issue and then re-run `mka bacon`; a full clean is usually unnecessary.
