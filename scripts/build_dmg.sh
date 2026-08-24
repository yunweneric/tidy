#!/usr/bin/env bash
#
# Builds Tidy.app and packages it into an unsigned (ad-hoc signed) DMG.
#
# The app is deliberately not signed with a Developer ID and not notarized, so
# Gatekeeper will quarantine it on other Macs. See the note printed at the end.
#
# Usage:
#   ./scripts/build_dmg.sh              # clean release build, then package
#   ./scripts/build_dmg.sh --skip-build # package whatever is already built
#   ./scripts/build_dmg.sh --open       # reveal the finished DMG in Finder

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Tidy"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
ENTITLEMENTS="macos/Runner/Release.entitlements"

SKIP_BUILD=false
OPEN_AFTER=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --open) OPEN_AFTER=true ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Version comes from pubspec so the DMG name tracks the app version.
VERSION="$(awk '/^version:/ { split($2, v, "+"); print v[1]; exit }' pubspec.yaml)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building $APP_NAME $VERSION"
if [[ "$SKIP_BUILD" == false ]]; then
  flutter build macos --release
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

# Ad-hoc signing. Frameworks first, then the bundle — signing the outer bundle
# invalidates nested code that is signed afterwards. (`--deep` would do this in
# one step but is deprecated and signs with the wrong entitlements.)
echo "==> Ad-hoc signing"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force --sign - --timestamp=none "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" -print0)

  while IFS= read -r -d '' dylib; do
    codesign --force --sign - --timestamp=none "$dylib"
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -name "*.dylib" -print0)
fi

codesign --force --sign - --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

codesign --verify --verbose=1 "$APP_PATH"

# Stage the drag-to-install layout: the app plus an /Applications shortcut.
echo "==> Staging disk image contents"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  -quiet \
  "$DMG_PATH"

hdiutil verify -quiet "$DMG_PATH"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"

cat <<EOF

Done: $DMG_PATH ($SIZE)

This DMG is unsigned and unnotarized, so macOS quarantines it after download.
To open it on another Mac:

  1. Drag $APP_NAME to Applications, then right-click the app and choose Open, or
  2. Run: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app

$APP_NAME runs outside the App Sandbox (it has to, in order to inspect
/Applications and ~/Library). Grant Full Disk Access in System Settings, then
reopen the app — macOS caches the decision per process, so the grant does not
take effect until relaunch.
EOF

if [[ "$OPEN_AFTER" == true ]]; then
  open -R "$DMG_PATH"
fi
