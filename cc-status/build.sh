#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building cc-status for arm64..."

echo "Building for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

mkdir -p bin

cp .build-arm64/arm64-apple-macosx/release/cc-status bin/cc-status

echo "Build complete: bin/cc-status (arm64)"
