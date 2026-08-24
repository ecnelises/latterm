#!/bin/bash

set -euo pipefail

readonly TEAM_ID="R7ZJJDMW42"
readonly BUNDLE_ID="com.ecnelises.latterm"
readonly APP_NAME="Latterm.app"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-latterm-notary}"

die() {
  echo "error: $*" >&2
  exit 1
}

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "usage: tools/release_latterm.sh <version>, for example 3.7.2026082401"
fi

readonly VERSION="$1"
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly OUTPUT_DIR="$ROOT/Build/Releases/$VERSION"
readonly WORK_DIR="$(mktemp -d /tmp/latterm-release.XXXXXX)"
readonly BUILD_DIR="$WORK_DIR/Build"
readonly VERSION_BACKUP="$WORK_DIR/version.txt"
readonly PLIST_BACKUP="$WORK_DIR/iTerm2.plist"
readonly APP_PATH="$BUILD_DIR/Deployment/$APP_NAME"
readonly PRENOTARIZED_ZIP="$WORK_DIR/Latterm-$VERSION-prenotarized.zip"
readonly FINAL_ZIP_NAME="Latterm-$VERSION.zip"
readonly FINAL_ZIP="$OUTPUT_DIR/$FINAL_ZIP_NAME"
readonly VERIFY_DIR="$WORK_DIR/verify"

restore_files() {
  if [[ -f "$VERSION_BACKUP" ]]; then
    cp "$VERSION_BACKUP" "$ROOT/version.txt"
  fi
  if [[ -f "$PLIST_BACKUP" ]]; then
    cp "$PLIST_BACKUP" "$ROOT/plists/iTerm2.plist"
  else
    rm -f "$ROOT/plists/iTerm2.plist"
  fi
  rm -rf "$WORK_DIR"
}
trap restore_files EXIT

cd "$ROOT"
[[ ! -e "$OUTPUT_DIR" ]] || die "release output already exists: $OUTPUT_DIR"

cp version.txt "$VERSION_BACKUP"
if [[ -f plists/iTerm2.plist ]]; then
  cp plists/iTerm2.plist "$PLIST_BACKUP"
fi

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
  die "no Developer ID Application identity is installed in the login keychain"
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  die "notarytool keychain profile '$NOTARY_PROFILE' is missing or invalid"
fi

printf '%s\n' "$VERSION" > version.txt

# Signed builds must retain the real HOME so Xcode can read the Developer ID
# identity from the login keychain. Unsigned contributor builds continue to use
# Makefile's isolated BUILD_HOME.
make BUILD_DIR="$BUILD_DIR" BUILD_HOME="$HOME" SIGNED=1 release
[[ -d "$APP_PATH" ]] || die "signed build did not produce $APP_PATH"

readonly ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
readonly ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
[[ "$ACTUAL_VERSION" == "$VERSION" ]] || die "built version is $ACTUAL_VERSION, expected $VERSION"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "bundle identifier is $ACTUAL_BUNDLE_ID, expected $BUNDLE_ID"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
readonly SIGNING_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$SIGNING_INFO" || die "app is not signed by team $TEAM_ID"
grep -q "^Identifier=$BUNDLE_ID$" <<<"$SIGNING_INFO" || die "signature identifier is not $BUNDLE_ID"
grep -q '^Authority=Developer ID Application:' <<<"$SIGNING_INFO" || die "app is not Developer ID signed"

(cd "$BUILD_DIR/Deployment" && zip -qry "$PRENOTARIZED_ZIP" "$APP_NAME")
xcrun notarytool submit "$PRENOTARIZED_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vvv -t exec "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
(cd "$BUILD_DIR/Deployment" && zip -qry "$FINAL_ZIP" "$APP_NAME")
(cd "$OUTPUT_DIR" && shasum -a 256 "$FINAL_ZIP_NAME" > "$FINAL_ZIP_NAME.sha256")
unzip -t "$FINAL_ZIP" >/dev/null

mkdir -p "$VERIFY_DIR"
ditto -x -k "$FINAL_ZIP" "$VERIFY_DIR"
readonly VERIFIED_APP="$VERIFY_DIR/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$VERIFIED_APP"
xcrun stapler validate "$VERIFIED_APP"
spctl -a -vvv -t exec "$VERIFIED_APP"

echo "Release package: $FINAL_ZIP"
echo "Checksum:        $FINAL_ZIP.sha256"
