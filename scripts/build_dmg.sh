#!/usr/bin/env bash
#
# Builds Tidy.app and packages it into an unsigned (ad-hoc signed) DMG.
#
# The app is deliberately not signed with a Developer ID and not notarized, so
# Gatekeeper quarantines it on any Mac other than the one that built it. See the
# note printed at the end.
#
# Usage:
#   ./scripts/build_dmg.sh                    # clean release build, then package
#   ./scripts/build_dmg.sh --skip-build       # package whatever is already built
#   ./scripts/build_dmg.sh --open             # reveal the finished DMG in Finder
#   ./scripts/build_dmg.sh --zip              # also emit Tidy-<v>-macos.zip
#   ./scripts/build_dmg.sh --version 1.2.0    # override the artifact version
#   ./scripts/build_dmg.sh --output-dir DIR   # write artifacts somewhere else
#   ./scripts/build_dmg.sh --flavor dev       # package the dev flavour instead

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ENTITLEMENTS="macos/Runner/Release.entitlements"

DIST_DIR="dist"
SKIP_BUILD=false
OPEN_AFTER=false
MAKE_ZIP=false
VERSION=""
# Empty means the unflavoured `Release` configuration — which is what CI and
# `release.sh` build, and which is identical to `--flavor prod`. Kept as the
# default so adding flavours changed nothing about the release path.
FLAVOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true ;;
    --open) OPEN_AFTER=true ;;
    --zip) MAKE_ZIP=true ;;
    --version) VERSION="${2:?--version needs a value}"; shift ;;
    --flavor) FLAVOR="${2:?--flavor needs a value}"; shift ;;
    --output-dir) DIST_DIR="${2:?--output-dir needs a value}"; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# The flavour decides three things at once, and they have to agree: which Xcode
# configuration is built, which scheme selects it, and what the resulting bundle
# is called — `Tidy Dev.app` under `Products/Release-dev`, not `Tidy.app` under
# `Products/Release`.
case "$FLAVOR" in
  "")   CONFIGURATION="Release";      SCHEME="Runner"; APP_NAME="Tidy" ;;
  prod) CONFIGURATION="Release-prod"; SCHEME="prod";   APP_NAME="Tidy" ;;
  dev)  CONFIGURATION="Release-dev";  SCHEME="dev";    APP_NAME="Tidy Dev" ;;
  *)    echo "Unknown flavor: $FLAVOR (expected dev or prod)" >&2; exit 1 ;;
esac

BUILD_DIR="build/macos/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# An array rather than a bare `${FLAVOR:+...}`, so an empty flavour contributes
# no argument at all instead of an empty one.
FLUTTER_FLAVOR_ARGS=()
if [[ -n "$FLAVOR" ]]; then
  FLUTTER_FLAVOR_ARGS=(--flavor "$FLAVOR")
fi

# Version comes from pubspec unless overridden, so the DMG name tracks the app.
# CI overrides it to append a short sha to builds that are not releases.
if [[ -z "$VERSION" ]]; then
  VERSION="$(awk '/^version:/ { split($2, v, "+"); print v[1]; exit }' pubspec.yaml)"
fi
if [[ -z "$VERSION" ]]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

# The artifact name drops the space so the updater's `Tidy-<version>-macos.zip`
# convention survives a flavoured build.
ARTIFACT_NAME="${APP_NAME// /-}"
DMG_PATH="$DIST_DIR/$ARTIFACT_NAME-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/$ARTIFACT_NAME-$VERSION-macos.zip"

echo "==> Building $APP_NAME $VERSION"

# xcodebuild directly rather than `flutter build macos`. The wrapper fails on
# some machines at destination resolution — it asks for arm64 while xcodebuild
# reports only an x86_64 destination — and this invocation still runs Flutter's
# own xcode_backend.sh build phase, so the bundle it produces is complete.
#
# `--config-only` is the half of the wrapper that still has to run: it writes
# Generated.xcconfig, unpacks Flutter/ephemeral and installs the pods, none of
# which exist in a fresh checkout. It stops short of calling xcodebuild.
if [[ "$SKIP_BUILD" == false ]]; then
  flutter pub get
  # `${a[@]+"${a[@]}"}` rather than a plain `"${a[@]}"`: macOS ships bash 3.2,
  # where an empty array under `set -u` is an *unset* variable and expanding it
  # aborts the script — so the unflavoured build, which is the one CI and every
  # release use, was the one path that could not run.
  flutter build macos --release --config-only \
    ${FLUTTER_FLAVOR_ARGS[@]+"${FLUTTER_FLAVOR_ARGS[@]}"}
  xcrun xcodebuild \
    -workspace macos/Runner.xcworkspace \
    -configuration "$CONFIGURATION" \
    -scheme "$SCHEME" \
    -derivedDataPath build/macos \
    -destination "platform=macOS,arch=arm64" \
    OBJROOT="$PWD/build/macos/Build/Intermediates.noindex" \
    SYMROOT="$PWD/build/macos/Build/Products" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build
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

mkdir -p "$DIST_DIR"

# Stage the drag-to-install layout: the app plus an /Applications shortcut.
echo "==> Staging disk image contents"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

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

# The in-app updater downloads a zip, not the disk image, and finds it by the
# name `Tidy-<version>-macos.zip`. ditto rather than zip: it is the only
# archiver that preserves the symlinks and extended attributes a bundle's
# signature depends on.
if [[ "$MAKE_ZIP" == true ]]; then
  echo "==> Creating $ZIP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
fi

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"

cat <<EOF

Done: $DMG_PATH ($SIZE)
EOF

if [[ "$MAKE_ZIP" == true ]]; then
  echo "      $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1 | tr -d ' '))"
fi

cat <<EOF

This DMG is unsigned and unnotarized, so macOS quarantines it after download.
To open it on another Mac:

  1. Drag $APP_NAME to Applications, then open System Settings ->
     Privacy & Security and choose "Open Anyway", or
  2. Run: xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app"

$APP_NAME runs outside the App Sandbox (it has to, in order to inspect
/Applications and ~/Library). Grant Full Disk Access in System Settings, then
reopen the app — macOS caches the decision per process, so the grant does not
take effect until relaunch.
EOF

if [[ "$OPEN_AFTER" == true ]]; then
  open -R "$DMG_PATH"
fi
