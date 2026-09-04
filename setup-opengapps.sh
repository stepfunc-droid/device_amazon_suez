#!/bin/bash
set -e

ROOT="${ANDROID_BUILD_TOP:-$PWD}"
MANIFEST_DIR="$ROOT/.repo/local_manifests"
SOURCE_MANIFEST="$ROOT/device/amazon/suez/manifests/opengapps.xml"
TARGET_MANIFEST="$MANIFEST_DIR/opengapps.xml"

if [ ! -d "$ROOT/.repo" ]; then
    echo "Run this from the root of the LineageOS source tree."
    exit 1
fi

mkdir -p "$MANIFEST_DIR"
cp "$SOURCE_MANIFEST" "$TARGET_MANIFEST"

echo "Installed OpenGApps local manifest: $TARGET_MANIFEST"

echo "Syncing OpenGApps build and ARM/ARM64 package sources..."
cd "$ROOT"
repo sync vendor/opengapps/build \
          vendor/opengapps/sources/all \
          vendor/opengapps/sources/arm \
          vendor/opengapps/sources/arm64

if command -v git-lfs >/dev/null 2>&1; then
    git lfs install
    for dir in \
        vendor/opengapps/build \
        vendor/opengapps/sources/all \
        vendor/opengapps/sources/arm \
        vendor/opengapps/sources/arm64; do
        echo "Pulling Git LFS objects in $dir..."
        git -C "$ROOT/$dir" lfs pull
    done
else
    echo "WARNING: git-lfs is not installed. Install it, then run this script again."
fi

echo "OpenGApps sources are ready. lineage_suez builds use GAPPS_VARIANT=pico."
