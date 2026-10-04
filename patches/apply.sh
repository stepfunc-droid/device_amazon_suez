#!/usr/bin/env bash
set -euo pipefail

rootdirectory="$PWD"

dirs=(
    bionic
    frameworks/av
    frameworks/base
    frameworks/native
    frameworks/opt/net/wifi
    hardware/interfaces
    packages/apps/FMRadio
    packages/apps/Settings
    system/bt
    system/core
    system/netd
    vendor/lineage
)

is_optional_patch() {
    case "$1" in
        bionic/0002-disable-fstack-protector.patch|\
        frameworks/base/0003-micro-g-add-enhanced-signature-spoofing.patch|\
        packages/apps/Settings/0001-micro-g-rebased-signature-spoofing-enablement.patch|\
        system/netd/0001-Don-t-fail-on-FTP-conntracking-failing.patch|\
        system/netd/0002-Accept-broken-rpfilter-match.patch)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

for dir in "${dirs[@]}"; do
    repo_dir="$rootdirectory/$dir"
    patch_dir="$rootdirectory/device/amazon/suez/patches/$dir"

    if [[ ! -d "$repo_dir" ]]; then
        echo "Missing source repository: $repo_dir" >&2
        exit 1
    fi

    shopt -s nullglob
    patches=("$patch_dir"/*.patch)
    shopt -u nullglob

    if (( ${#patches[@]} == 0 )); then
        continue
    fi

    echo "Checking $dir patches..."

    for patch in "${patches[@]}"; do
        relative="${patch#"$rootdirectory/device/amazon/suez/patches/"}"

        if is_optional_patch "$relative"; then
            echo "  OPTIONAL     $relative (not applied by default)"
            continue
        fi

        if git -C "$repo_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
            echo "  APPLIED      $relative"
        elif git -C "$repo_dir" apply --check "$patch" >/dev/null 2>&1; then
            git -C "$repo_dir" apply "$patch"
            echo "  NEW          $relative"
        else
            echo "  CONFLICT     $relative" >&2
            echo "Patch is neither cleanly applicable nor already applied." >&2
            exit 1
        fi
    done

    echo
done

echo "Patch audit/application complete."
