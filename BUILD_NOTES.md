# Suez LineageOS 16 build notes

This file records the build/rebuild pitfalls found while working on the Amazon Fire HD 10 (2017), codename `suez`, so the next build does not have to rediscover them.

The first fully successful rebuild covered by these notes completed on 2026-09-04 and produced:

```text
out/target/product/suez/lineage-16.0-20260904-UNOFFICIAL-suez.zip
```

## Build target

- Device: Amazon Fire HD 10 (2017), `suez`
- SoC: MediaTek MT8173
- GPU: PowerVR GX6250
- ROM: LineageOS 16.0 / Android 9
- Product: `lineage_suez-userdebug`
- GApps, if needed: OpenGApps **ARM64 / Android 9.0 / pico**

## Source layout

Expected source layout under the LineageOS root:

```text
~/lineage-16.0/
├── device/amazon/suez
├── kernel/amazon/suez
└── vendor/amazon/suez
```

The device tree is this repository. The kernel used for the successful build is:

```text
https://github.com/lineage16-suez/kernel_amazon_suez
branch: lineage-16.0
```

Do **not** replace the generated `vendor/amazon/suez` tree wholesale with an unrelated suez vendor repository. That caused incompatible NVRAM packaging. The working vendor tree was extracted from the correct FireOS stock image, then the required non-stock Widevine L3 blobs were restored separately.

## Normal rebuild

From the LineageOS source root:

```bash
cd ~/lineage-16.0

git -C device/amazon/suez pull

source build/envsetup.sh
lunch lineage_suez-userdebug
mka bacon
```

### Fish shell warning

`build/envsetup.sh` is Bash syntax. Do not source it directly from fish.

Use an interactive Bash shell:

```bash
bash
source build/envsetup.sh
lunch lineage_suez-userdebug
mka bacon
```

or one command:

```bash
bash -lc 'source build/envsetup.sh && lunch lineage_suez-userdebug && mka bacon'
```

If packages were added/removed from the system image, run an install clean first so stale APKs do not remain in `out/`:

```bash
m installclean
mka bacon
```

A full `make clean` is normally unnecessary and wastes a very large amount of rebuild time.

## Host build dependencies that actually mattered

The build host used here was Debian 12 x86_64.

A useful baseline package set is:

```bash
sudo apt install -y \
  bc bison build-essential ccache curl flex \
  g++-multilib gcc-multilib git git-lfs gnupg gperf \
  imagemagick \
  lib32readline-dev lib32z1-dev libelf-dev libssl-dev \
  libxml2 libxml2-utils lz4 lzop pngcrush rsync schedtool \
  squashfs-tools xsltproc zip unzip zlib1g-dev \
  libncurses-dev lib32ncurses-dev \
  file patch perl python3 python3-pip wget xxd xz-utils
```

### ImageMagick is required

Without ImageMagick the build stops while generating the boot animation:

```text
The boot animation could not be generated as ImageMagick is not installed
vendor/lineage/bootanimation/Android.mk:50: error: stop.
```

Install:

```bash
sudo apt install -y imagemagick
```

### Old Clang needs ncurses ABI 5

One old prebuilt Clang binary failed on Debian 12 with:

```text
error while loading shared libraries: libncurses.so.5: cannot open shared object file
```

Install the compatibility libraries:

```bash
sudo apt install -y libncurses5 libtinfo5
```

Do **not** fake this by symlinking `.so.6` to `.so.5`.

## Python: use a real Python 2.7 with zlib

This was one of the most time-consuming host issues.

LOS16/Pie build scripts still contain Python 2 assumptions. Two separate mechanisms matter:

1. old compiler wrapper scripts use a hardcoded `#!/usr/bin/python` shebang;
2. Soong-generated Python launchers may explicitly search for a command named `python2.7`.

The bundled checkout at:

```text
prebuilts/python/linux-x86/2.7.5/bin/python
```

reported Python 2.7.5 but had no zlib module:

```text
ImportError: No module named zlib
```

That later caused:

```text
can't decompress data; zlib not available
```

### Do not substitute Python 3

Temporarily pointing `python`/`python2.7` at Python 3 allowed some tools to run, but then old Pie scripts failed on Python 2/3 semantic differences, for example:

```text
TypeError: a bytes-like object is required, not 'str'
```

in:

```text
system/sepolicy/build/file_utils.py
```

Do not patch old build scripts one-by-one to make Python 3 work. Use real Python 2 instead.

### Working solution: Miniconda2 Python 2.7.18

A prebuilt Miniconda2 install worked and avoided compiling Python locally:

```bash
cd /tmp
wget https://repo.anaconda.com/miniconda/Miniconda2-py27_4.8.3-Linux-x86_64.sh
bash Miniconda2-py27_4.8.3-Linux-x86_64.sh -b -p "$HOME/miniconda2"
```

Verify:

```bash
~/miniconda2/bin/python2.7 --version
~/miniconda2/bin/python2.7 -c 'import zlib, zipfile, tempfile; print(zlib.ZLIB_VERSION)'
```

The successful environment reported:

```text
Python 2.7.18 :: Anaconda, Inc.
1.2.11
```

On a dedicated build machine/VM, connect it to the names the old build expects:

```bash
sudo ln -sf "$HOME/miniconda2/bin/python2.7" /usr/bin/python
sudo ln -sf "$HOME/miniconda2/bin/python2.7" /usr/local/bin/python2.7
```

Verify before starting a long build:

```bash
python --version
python2.7 --version
python2.7 -c 'import zlib; print(zlib.ZLIB_VERSION)'
```

Also test the previously failing generated tool:

```bash
cd ~/lineage-16.0
out/soong/host/linux-x86/bin/generate_operator_out \
  art/compiler \
  art/compiler/dex/dex_to_dex_compiler.h \
  >/tmp/operator-test.cc

echo $?
```

Expected result: `0`.

If `system/sepolicy/build/file_utils.py` was temporarily modified for Python 3 compatibility, restore it before continuing:

```bash
git -C system/sepolicy checkout -- build/file_utils.py
```

## Proprietary blobs: use FireOS 5.3.7.3

The working stock blob base is FireOS 5.3.7.3 for Fire HD 10 7th Gen / `suez` / KFSUWI:

```text
Fire OS: 5.3.7.3
Build:   659655820
File:    update-kindle-40.6.5.9_user_659655820.bin
MD5:     c52df011202841ff410023c248f6a188
```

The update archive contains `system.new.dat` and `system.transfer.list` directly; it is not Brotli-compressed.

Example extraction:

```bash
mkdir -p fireos-5.3.7.3
unzip update-kindle-40.6.5.9_user_659655820.bin \
  system.new.dat \
  system.transfer.list \
  -d fireos-5.3.7.3
```

Convert the sparse/block OTA payload:

```bash
git clone https://github.com/xpirt/sdat2img.git
python3 sdat2img/sdat2img.py \
  fireos-5.3.7.3/system.transfer.list \
  fireos-5.3.7.3/system.new.dat \
  fireos-5.3.7.3/system.img
```

Mount read-only and extract blobs:

```bash
sudo mkdir -p /mnt/suez-fireos
sudo mount -o loop,ro ~/fireos-5.3.7.3/system.img /mnt/suez-fireos

cd ~/lineage-16.0
rm -rf vendor/amazon/suez
device/amazon/suez/extract-files.sh /mnt/suez-fireos
```

Important: re-running stock extraction overwrites the generated vendor tree, so the non-stock Widevine blobs described below must be restored afterward.

## NVRAM: generate an actual `libnvram` module

The Bluetooth vendor library links against a module named `libnvram`:

```make
LOCAL_SHARED_LIBRARIES := \
    liblog \
    libcutils \
    libnvram
```

A raw vendor copy of `libnvram.so` is not enough; the build graph needs a prebuilt `libnvram` module for both 32-bit and 64-bit variants.

If the build fails with:

```text
libbluetooth_mtk ... missing libnvram
```

change the two `libnvram` entries in `device/amazon/suez/proprietary-files.txt` from ordinary copy entries to generated prebuilt modules by adding a leading `-`:

```text
-lib/libnvram.so:vendor/lib/libnvram.so
-lib64/libnvram.so:vendor/lib64/libnvram.so
```

Then regenerate vendor makefiles:

```bash
device/amazon/suez/setup-makefiles.sh
```

The generated `vendor/amazon/suez/Android.mk` should then contain one multilib prebuilt module similar to:

```make
include $(CLEAR_VARS)
LOCAL_MODULE := libnvram
LOCAL_MODULE_OWNER := amazon
LOCAL_SRC_FILES_64 := proprietary/vendor/lib64/libnvram.so
LOCAL_SRC_FILES_32 := proprietary/vendor/lib/libnvram.so
LOCAL_MULTILIB := both
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_VENDOR_MODULE := true
include $(BUILD_PREBUILT)
```

Do not use `ALLOW_MISSING_DEPENDENCIES=true` to hide this; the library is a real dependency.

## Widevine L3 blobs are intentionally non-stock

The current LineageOS suez tree expects six Widevine L3 files that were kanged from `hermes`; they are not all supplied by the FireOS stock extraction.

Expected files and SHA1 values:

```text
vendor/bin/hw/android.hardware.drm@1.0-service.widevine
  d2c5e233ad22903a1ea3379c9d325d0f2877d459
vendor/etc/init/android.hardware.drm@1.0-service.widevine.rc
  51a3168a0dbc064d78ee11ca83614c0cd2e6daa5
vendor/lib/libwvhidl.so
  4c3f12cab6bac3c10db27f9bf3f08f0e058289f0
vendor/lib64/libwvhidl.so
  31528465d11853cb67f22b9161d7885823af449e
vendor/lib/mediadrm/libwvdrmengine.so
  5a328e3a228c7ba6da032af829e4775352c84545
vendor/lib64/mediadrm/libwvdrmengine.so
  f7f4f34213df3d57dbb7b726048b1ab244bb61f7
```

A third-party vendor repository contained five matching files, but its **32-bit** `vendor/lib/mediadrm/libwvdrmengine.so` did not match. The correct 32-bit file was recovered from a working suez ROM and matched:

```text
5a328e3a228c7ba6da032af829e4775352c84545
```

If the build fails with a missing Widevine service such as:

```text
ninja: error: 'vendor/amazon/suez/proprietary/vendor/bin/hw/android.hardware.drm@1.0-service.widevine', missing and no known rule to make it
```

restore these six blobs to `vendor/amazon/suez/proprietary/...` with the expected hashes. Merely replacing the blob files does not require a clean build.

## ClearKey: malformed LOS16 backport

A later build failure came from:

```text
frameworks/av/drm/mediadrm/plugins/clearkey/hidl/include/DrmPlugin.h
```

with:

```text
error: unknown type name 'DeviceFiles'
```

The problematic LOS16 backport added a valid `mSecurityLevelLock`, but also carried three fields from a newer ClearKey implementation even though Pie's HIDL implementation does not define/use `DeviceFiles`.

Remove only these three stray fields:

```cpp
DeviceFiles mFileHandle GUARDED_BY(mFileHandleLock);
Mutex mFileHandleLock;
Mutex mSecureStopLock;
```

Keep:

```cpp
Mutex mSecurityLevelLock;
```

One direct fix is:

```bash
sed -i \
  -e '/DeviceFiles mFileHandle GUARDED_BY(mFileHandleLock);/d' \
  -e '/Mutex mFileHandleLock;/d' \
  -e '/Mutex mSecureStopLock;/d' \
  frameworks/av/drm/mediadrm/plugins/clearkey/hidl/include/DrmPlugin.h
```

This came from LineageOS commit `2692e4bcdba06eec20424291acaac5669acf581f` (`setSecurityLevel in clearkey`). Do not import the modern `DeviceFiles` implementation just to satisfy the compiler; it does not belong to this Pie HIDL implementation.

For long-term reproducibility, this source-tree fix should eventually be represented as a device patch rather than relying on a manual edit.

## WebView prebuilt: Git LFS and nested repository

A build can fail while signing WebView with:

```text
java.util.zip.ZipException: zip END header not found
```

The failing file was:

```text
external/chromium-webview/prebuilt/arm64/webview.apk
```

The parent directory `external/chromium-webview` is **not** itself the Git repository for this prebuilt, so running `git lfs pull` there gives:

```text
Not in a Git repository.
```

The actual project is:

```text
external/chromium-webview/prebuilt/arm64
```

Run:

```bash
cd ~/lineage-16.0/external/chromium-webview/prebuilt/arm64
git lfs pull
```

Validate the result before rebuilding:

```bash
ls -lh webview.apk
file webview.apk
unzip -t webview.apk >/dev/null
echo $?
```

The working APK was about 233 MB, `file` recognized it as an Android package, and `unzip -t` returned `0`.

If needed, sync only this project instead of the entire source tree:

```bash
cd ~/lineage-16.0
repo sync -c -j1 --force-sync external/chromium-webview/prebuilt/arm64
```

Then run `git lfs pull` inside that nested project again.

## Incremental build failures near the end

Old Pie/LOS16 builds can accumulate inconsistent intermediates after many interrupted/retried builds. Prefer cleaning the smallest affected module rather than deleting all of `out/`.

### `apache-xml`: hiddenapi says no DEX files

Failure:

```text
hiddenapi: No DEX files specified
At least one --dex parameter must be specified.
```

The `apache-xml_intermediates/dex` directory had no `classes*.dex` for the next hiddenapi step.

Rebuild only that module:

```bash
cd ~/lineage-16.0
make clean-apache-xml
make apache-xml -j"$(nproc)"
```

Then continue the full build.

### `ims-ext-common`: `ImsManager` missing

While rebuilding dependencies, `ims-ext-common` can fail with:

```text
vendor/codeaurora/telephony/ims/src/org/codeaurora/ims/QtiImsExtManager.java:
error: cannot find symbol
import com.android.ims.ImsManager;
```

`ims-ext-common` correctly depends on `ims-common`; `ImsManager.java` belongs to `frameworks/opt/net/ims`. If the source file exists but the generated header jar does not contain `ImsManager.class`, clean/rebuild `ims-common` rather than modifying Qualcomm IMS source:

```bash
make clean-ims-common
make ims-common -j"$(nproc)"
```

Verify:

```bash
jar tf \
  out/target/common/obj/JAVA_LIBRARIES/ims-common_intermediates/classes-header.jar \
  | grep 'com/android/ims/ImsManager'
```

Then rebuild `ims-ext-common` or resume `mka bacon`.

### Many apps fail ProGuard with `output jar is empty`

Near the end of the successful build, several unrelated apps failed together, including `BasicDreams`, `BluetoothMidiService`, `BookmarkProvider`, `CertInstaller`, `CompanionDeviceManager`, and `KeyChain`:

```text
ProGuard, version 5.1
Error: The output jar is empty. Did you specify the proper '-keep' options?
```

Because many unrelated apps failed identically at once, this was stale/inconsistent `APPS` intermediate state rather than six independent ProGuard configuration bugs.

The working fix was to remove only the common app intermediates and resume:

```bash
cd ~/lineage-16.0
rm -rf out/target/common/obj/APPS
mka bacon
```

Do not disable ProGuard globally and do not delete the whole `out/` directory for this symptom.

## Non-fatal messages seen during the successful build

This recovery-ramdisk message appeared but was **not** the command that stopped the build:

```text
cp: cannot stat '.../out/target/product/suez/root/init.recovery.*.rc': No such file or directory
```

The build continued past it. Always identify the actual `FAILED:` block / final Ninja error before changing source.

Likewise, warnings such as old DroidDoc API messages and LLVM `ThreadPool with 1 threads` warnings were not fatal.

## Incremental build behavior and disk usage

Each new Ninja invocation starts its displayed percentage at 0/1% again. That does **not** mean the full ROM is recompiling from scratch. Watch the total target count: it drops sharply as completed outputs are reused.

Do not run `make clean` just because the displayed percentage reset.

`out/` can consume tens of GB and that is expected. During the final successful packaging run the disk had only about 10 GB free and still completed, but more headroom is safer.

Useful checks:

```bash
df -h ~/lineage-16.0
du -sh out
du -h --max-depth=2 out 2>/dev/null | sort -h | tail -20
du -sh ~/.ccache 2>/dev/null
```

Near 99-100%, packaging creates OTA/final ZIP artifacts and can still need several GB of temporary space. Do not delete build intermediates while packaging is running.

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

### Debian ADB permissions

On Debian, install the tools and common udev rules with:

```bash
sudo apt install -y \
  android-tools-adb android-tools-fastboot \
  android-sdk-platform-tools-common
```

If an Amazon device still shows `no permissions`, a rule for Amazon's USB vendor ID may be needed:

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1949", MODE="0660", GROUP="plugdev", TAG+="uaccess"' \
  | sudo tee /etc/udev/rules.d/51-amazon-android.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
adb kill-server
```

Unplug/replug USB afterward.

If TWRP says `unable to mount storage`, ADB sideload can still work because it does not require copying the ZIP into internal storage. If the recovery ends with `Done`/successful install, rebooting System is appropriate.

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
- prefer targeted `repo sync` for one broken project instead of re-syncing the entire tree;
- when changing the list of installed system packages, use `m installclean` before the next build;
- when a build stops during ckati/product configuration, fix the makefile issue and then re-run `mka bacon`; a full clean is usually unnecessary;
- when a late incremental build fails in one module, clean that module/intermediate first rather than deleting all of `out/`;
- preserve locally required non-stock blobs and source patches before re-extracting or resetting projects.
