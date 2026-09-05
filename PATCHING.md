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
frameworks/opt/net/wifi|frameworks/opt/net/wifi/0001-Passpoint-do-not-send-ANQP-for-WifiMetrics.patch
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
frameworks/opt/net/wifi/0001-Passpoint-do-not-send-ANQP-for-WifiMetrics.patch
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

## Wi-Fi instability: unnecessary ANQP/GAS requests from `WifiMetrics`

Patch:

```text
frameworks/opt/net/wifi/0001-Passpoint-do-not-send-ANQP-for-WifiMetrics.patch
```

This is a backport of the upstream Android Wi-Fi fix from commit `e35f422b08d89395a1f011353c707174b9bb53e0` (`Bug: 141624212`).

### Symptom on suez

The device could remain visibly associated with Wi-Fi while the actual data path became unusable:

```text
wlan0 remains UP / LOWER_UP
Wi-Fi UI still appears connected
RSSI reported by the MT6630 driver drops to 0
gateway ping begins timing out
8.8.8.8 ping also times out
Android later reports "No internet"
```

During the failure the MT6630 driver was also observed logging messages such as:

```text
BAR for a NULL STA_REC, ucStaRecIdx = 255
nicUpdateLinkQuality: Rssi=0, NewRssi=0
```

Those messages are useful symptoms of the broken driver/firmware connection state, but they were not the earliest trigger found in the trace.

Power saving was tested separately and is not the primary cause: the same failure occurred while `iw dev wlan0 get power_save` reported `Power save: off`.

### Trigger found in the logs

A working connection on 5 GHz could be followed by an ANQP/GAS query to another AP on a different channel. The MT6630 AIS state machine then entered an off-channel remain-on-channel operation. Shortly afterwards RSSI dropped to zero and the data path stalled.

The important sequence was:

```text
normal connected traffic on the current AP
        -> full-band Wi-Fi scan
        -> ANQP request is initiated for an interworking AP
        -> GAS query / remain-on-channel on another channel
        -> MT6630 returns from off-channel operation in a bad connection state
        -> RSSI becomes 0
        -> gateway traffic stalls
        -> Android still temporarily believes the network is connected
        -> connectivity validation fails / "No internet"
```

This made the failure look like a random MT6630 driver problem, but the off-channel operation was being triggered unnecessarily by the Android framework.

### Why ANQP happened even though Passpoint was not enabled

The device does **not** advertise Passpoint as a platform feature:

```text
$ pm list features | grep -Ei "wifi|passpoint"
feature:android.hardware.wifi
feature:android.hardware.wifi.direct
```

There is no `android.hardware.wifi.passpoint` permission XML installed, and `dumpsys wifi` showed zero configured Passpoint providers.

The device Wi-Fi configuration does contain:

```text
/vendor/etc/wifi/wpa_supplicant.conf:hs20=1
```

However, `hs20=1` by itself was not the reason for the repeated queries. The Android 9 framework created `PasspointManager` for Wi-Fi metrics even without a declared Passpoint feature.

The problematic Android 9 path was:

```text
WifiConnectivityManager
        -> full-band scan results
        -> WifiMetrics.incrementAvailableNetworksHistograms()
        -> interworking AP detected
        -> PasspointManager.matchProvider(scanResult)
        -> ANQP cache miss
        -> ANQPRequestManager.requestANQPElements()
        -> wpa_supplicant GAS/ANQP exchange
        -> MT6630 off-channel remain-on-channel
```

So the ANQP request was being sent **for metrics collection**, not because the user had configured or connected to a Passpoint network.

This was confirmed by runtime logs such as:

```text
HS20: ANQP initiated on <BSSID>
PasspointManager: ANQP entry not found for: <BSSID>
wpa_supplicant: ANQP-QUERY-DONE ... result=FAILURE
ANQPRequestManager: Not allowed to send ANQP request ... for another N seconds
```

The increasing hold-off time is expected behavior in `ANQPRequestManager` after repeated unanswered/failed requests; it can back off to several minutes. That also explains why the Wi-Fi failure could appear intermittent rather than continuous.

### Upstream fix and local backport

Upstream later fixed this exact class of bug with:

```text
[Passpoint] Do not initiate ANQP query for metrics update
```

The fix makes provider matching optionally cache-only. For metrics collection the call becomes conceptually:

```java
mPasspointManager.matchProvider(scanResult, false);
```

where `false` means an ANQP cache miss must **not** initiate a new ANQP request.

The suez backport does the same thing:

- `WifiMetrics` may inspect already cached ANQP data;
- `WifiMetrics` may not start a new ANQP/GAS transaction;
- normal Passpoint matching keeps its existing behavior and may still request ANQP when appropriate;
- the MT6630 driver's general remain-on-channel support is not disabled;
- `hs20=1` is left intact.

This is intentionally narrower and safer than disabling remain-on-channel, Wi-Fi scanning, or all HS2.0 support in the driver.

### Applying only this patch to an existing source tree

Do not re-run the full patch script on a source tree where other patches are already applied.

```bash
cd ~/lineage-16.0

PATCH="$PWD/device/amazon/suez/patches/frameworks/opt/net/wifi/0001-Passpoint-do-not-send-ANQP-for-WifiMetrics.patch"

git -C frameworks/opt/net/wifi apply --check "$PATCH"
git -C frameworks/opt/net/wifi apply "$PATCH"
```

Verify:

```bash
git -C frameworks/opt/net/wifi apply --reverse --check "$PATCH" && \
  echo "ANQP PATCH APPLIED"
```

This patch only changes `frameworks/opt/net/wifi`; an `installclean` is not normally required just for this patch before rebuilding.

### Post-fix validation

After flashing a build containing the patch, clear the old log buffer and use the device normally through multiple Wi-Fi scans:

```bash
adb logcat -c
```

Then check for new framework-triggered ANQP/GAS activity:

```bash
adb logcat -d -b all | grep -Ei \
'ANQP initiated|GAS-QUERY-START|ANQP-QUERY-DONE|ANQP entry not found|ANQPRequestManager'
```

`ANQP entry not found` may still appear because the framework can inspect the cache. With no configured Passpoint provider, new metrics-only activity such as the following should no longer be generated:

```text
HS20: ANQP initiated
GAS-QUERY-START
ANQP-QUERY-DONE
```

The functional regression test is equally important: the old sequence `RSSI -> 0`, gateway packet loss, and `No internet` should no longer recur under normal use.

Initial testing after applying the backport showed the Wi-Fi connection behaving normally with no immediate recurrence of the previous failure. Treat that as an initial validation rather than proof of permanent stability; longer normal-use soak testing is still appropriate.

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
