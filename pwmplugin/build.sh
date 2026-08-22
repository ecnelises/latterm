#!/bin/bash

set -e

# Code signing setup
# Use Developer ID Application for distribution, or ad-hoc signing for local development
# Can be overridden with CODESIGN_IDENTITY environment variable
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    # Try to find Developer ID Application certificate (use the first one if multiple exist)
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | grep -o '[0-9A-F]\{40\}') || true
fi

sign_binary() {
    local name=$1
    echo "Code signing $name..."
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "Signing with certificate: $SIGNING_IDENTITY"
        codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGNING_IDENTITY" .build/release/$name
    else
        echo "Warning: No Developer ID Application certificate found, using ad-hoc signature (development only)"
        codesign -s - .build/release/$name
    fi
}

echo "Building password manager adapters for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

mkdir -p .build/release

copy_arm64() {
    local name=$1
    echo ""
    echo "Copying arm64 binary for $name..."
    cp ".build-arm64/arm64-apple-macosx/release/$name" ".build/release/$name"

    sign_binary "$name"

    echo "Build complete: .build/release/$name (arm64)"
    cp .build/release/$name binaries/
}

copy_arm64 "iterm2-keepassxc-adapter"
copy_arm64 "iterm2-bitwarden-adapter"
copy_arm64 "iterm2-keeper-adapter"

echo ""
echo "All builds complete!"
