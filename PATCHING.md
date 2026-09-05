# Suez source patch notes

The patch files under `device/amazon/suez/patches/` are **not applied automatically by the Android build**. Merely syncing or pulling this device tree does not put those changes into `frameworks/*`, `system/*`, `bionic`, or the other target repositories.

The repository provides:

```bash
device/amazon/suez/patches/apply.sh
```

That script is intended for a fresh/reset source tree. It changes into each target repository and runs `git apply` on the patches for that repository.

## Do not blindly re-run `apply.sh`

`git apply` is not idempotent. A source tree can also be in a mixed state where some patches are already applied and others are not. Running the full script against such a tree will fail part-way through and makes it hard to know which patches actually entered the build.

Audit the patch state first. `git apply --reverse --check` means the patch is already present; `git apply --check` means it can still be applied cleanly.

From the LineageOS source root:

```bash
cd ~/lineage-16.0
ROOT="$PWD"

while IFS='|' read -r repo patch; do
    [ -z "$repo" ] && continue
    full="$ROOT/device/amazon/suez/patches/$patch"

    if git -C "$repo" apply --reverse --check "$full" >/dev/null 2>&1; then
        printf "APPLIED      %s\n" "$patch"
    elif git -C "$repo" apply --check "$full" >/dev/null 2>&1; then
        printf "NOT_APPLIED  %s\n" "$patch"
    else
        printf "CONFLICT     %s\n" "$patch"
    fi
done <<'EOF'
bionic|bionic/0001-pthread-patch.patch
frameworks/av|frameworks/av/0001-Disable-vndk-for-omx.patch
frameworks/av|frameworks/av/0002-mediatek-Port-AV-changes.patch
frameworks/av|frameworks/av/0004-Add-support-of-YUV-color-profiles.patch
frameworks/av|frameworks/av/0006-MTK-Omx-video-decoder-crop-info.patch
frameworks/av|frameworks/av/0009-Fix-DpBlitStream-leak.patch
frameworks/base|frameworks/base/0001-Hardware-bitmaps-support-workaround.patch
frameworks/base|frameworks/base/0002-zygote-Add-ged-to-whitelisted-paths.patch
frameworks/base|frameworks/base/0005-SystemUI-avoid-hardware-bitmaps-for-navigation-keys.patch
frameworks/native|frameworks/native/0001-Add-support-of-YUV-color-profiles.patch
hardware/interfaces|hardware/interfaces/0001-HWC2On1Adapter-Fix-fence-leak.patch
hardware/interfaces|hardware/interfaces/0002-MediaTek-P-hw-interfaces.patch
system/core|system/core/0001-libsuspend-readd-earlysuspend.patch
system/core|system/core/0002-liblog-Add-__xlog_buf_printf.patch
system/core|system/core/0003-libnetutils-add-MTK-bits-in-ifc_utils.c.patch
vendor/lineage|vendor/lineage/0002-add-bromite-webview-overlay.patch
EOF
```

Interpretation:

```text
APPLIED      patch is already in the actual source tree
NOT_APPLIED  patch is absent and can be applied cleanly
CONFLICT     patch is partially present, based on a different source revision, or depends on another patch
```

For an existing source tree, apply only the required `NOT_APPLIED` patches. Do not run the whole patch set just because the files exist.

## Baseline patches for this MT8173 build

The following are the important MTK/PowerVR/legacy-blob compatibility patches currently considered required or recommended for suez:

```text
bionic/0001-pthread-patch.patch
frameworks/av/0001-Disable-vndk-for-omx.patch
frameworks/av/0002-mediatek-Port-AV-changes.patch
frameworks/av/0004-Add-support-of-YUV-color-profiles.patch
frameworks/av/0006-MTK-Omx-video-decoder-crop-info.patch
frameworks/av/0009-Fix-DpBlitStream-leak.patch
frameworks/base/0001-Hardware-bitmaps-support-workaround.patch
frameworks/base/0002-zygote-Add-ged-to-whitelisted-paths.patch
frameworks/base/0005-SystemUI-avoid-hardware-bitmaps-for-navigation-keys.patch
frameworks/native/0001-Add-support-of-YUV-color-profiles.patch
hardware/interfaces/0001-HWC2On1Adapter-Fix-fence-leak.patch
hardware/interfaces/0002-MediaTek-P-hw-interfaces.patch
system/core/0001-libsuspend-readd-earlysuspend.patch
system/core/0002-liblog-Add-__xlog_buf_printf.patch
system/core/0003-libnetutils-add-MTK-bits-in-ifc_utils.c.patch
vendor/lineage/0002-add-bromite-webview-overlay.patch
```

Do **not** assume every patch in `patches/` belongs in every build. In particular:

- the microG signature-spoofing patches are unnecessary when using OpenGApps;
- the `system/netd` patches alter tethering/conntrack behavior and are not a general Wi-Fi stability fix;
- `bionic/0002-disable-fstack-protector.patch` weakens stack-protector coverage and should not be used without a concrete compatibility reason.

## Patch ordering

`frameworks/av/0009-Fix-DpBlitStream-leak.patch` modifies code introduced by `frameworks/av/0004-Add-support-of-YUV-color-profiles.patch`. Apply `0004` before `0009`.

The two PowerVR/SystemUI patches are separate fixes and should remain separate:

```text
frameworks/base/0001-Hardware-bitmaps-support-workaround.patch
frameworks/base/0005-SystemUI-avoid-hardware-bitmaps-for-navigation-keys.patch
```

## `libdpframework` Soong module

`frameworks/av/0004-Add-support-of-YUV-color-profiles.patch` adds `libdpframework` to `shared_libs`. Copying `libdpframework.so` into the vendor image is not enough: Soong needs a module named `libdpframework` in the build graph.

If Soong fails with:

```text
"libstagefright_color_conversion" depends on undefined module "libdpframework"
```

verify the blobs:

```bash
ls -l \
  vendor/amazon/suez/proprietary/vendor/lib/libdpframework.so \
  vendor/amazon/suez/proprietary/vendor/lib64/libdpframework.so
```

Then define the vendor prebuilt in `vendor/amazon/suez/Android.bp` if it is not already generated there:

```bp
cc_prebuilt_library_shared {
    name: "libdpframework",
    vendor: true,
    target: {
        android_arm: {
            srcs: ["proprietary/vendor/lib/libdpframework.so"],
        },
        android_arm64: {
            srcs: ["proprietary/vendor/lib64/libdpframework.so"],
        },
    },
    strip: {
        none: true,
    },
}
```

Do not remove the `libdpframework` dependency just to make Soong pass; it is part of the MTK YUV/color-conversion path added by AV `0004`.

## Rebuild after applying core patches

When patches have been added across core framework repositories, use an install clean before the first rebuild:

```bash
cd ~/lineage-16.0
source build/envsetup.sh
lunch lineage_suez-userdebug
m installclean
mka bacon
```

A full `make clean` is still normally unnecessary.
