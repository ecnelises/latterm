#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure protobuf symlinks exist
./setup.sh

# Code signing setup
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | grep -o '[0-9A-F]\{40\}') || true
fi

sign_binary() {
    local name=$1
    echo "Code signing $name..."
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "Signing with certificate: $SIGNING_IDENTITY"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" .build/release/$name
    else
        echo "Warning: No Developer ID Application certificate found, using ad-hoc signature (development only)"
        codesign -s - .build/release/$name
    fi
}

echo "Building it2 for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

mkdir -p .build/release
cp .build-arm64/arm64-apple-macosx/release/it2 .build/release/it2

sign_binary "it2"

echo "Build complete: .build/release/it2 (arm64)"

echo ""
echo "Build complete!"
