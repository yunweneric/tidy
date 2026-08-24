#!/usr/bin/env bash
#
# Builds Tidy.app and packages it into a DMG.
#
# Signing is decided by what is available, so the same script serves a local
# smoke build and the release pipeline:
#
#   * A "Developer ID Application" identity in the keychain (or SIGNING_IDENTITY)
#     => hardened-runtime Developer ID signing, ready for notarization.
#   * Nothing => ad-hoc signing (`codesign --sign -`), which Gatekeeper
#     quarantines on any Mac other than the one that built it.
#
# Notarization runs when Apple credentials are present in the environment
# (APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID, or
# NOTARY_KEYCHAIN_PROFILE) and the build is Developer ID signed.
#
# Usage:
#   ./scripts/build_dmg.sh                    # build, sign, package
#   ./scripts/build_dmg.sh --skip-build       # package whatever is already built
#   ./scripts/build_dmg.sh --open             # reveal the finished DMG in Finder
#   ./scripts/build_dmg.sh --adhoc            # force ad-hoc signing
#   ./scripts/build_dmg.sh --identity "Developer ID Application: Name (TEAMID)"
#   ./scripts/build_dmg.sh --notarize         # fail (don't skip) if creds are missing
#   ./scripts/build_dmg.sh --no-notarize      # sign, but never call Apple
#   ./scripts/build_dmg.sh --version 1.2.0 --output-dir build/dist

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Tidy"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"

DIST_DIR="dist"
SKIP_BUILD=false
OPEN_AFTER=false
FORCE_ADHOC=false
NOTARIZE_MODE="auto" # auto | always | never
IDENTITY="${SIGNING_IDENTITY:-}"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true ;;
    --open) OPEN_AFTER=true ;;
    --adhoc) FORCE_ADHOC=true ;;
    --notarize) NOTARIZE_MODE="always" ;;
    --no-notarize) NOTARIZE_MODE="never" ;;
    --identity) IDENTITY="${2:?--identity needs a value}"; shift ;;
    --version) VERSION="${2:?--version needs a value}"; shift ;;
    --output-dir) DIST_DIR="${2:?--output-dir needs a value}"; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# The repo is pinned to a Flutter version through FVM; CI installs that same
# version on PATH instead, so only use the wrapper when it is really there.
if [[ -f ".fvmrc" ]] && command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

# Version comes from pubspec unless overridden, so the DMG name tracks the app.
if [[ -z "$VERSION" ]]; then
  VERSION="$(awk '/^version:/ { split($2, v, "+"); print v[1]; exit }' pubspec.yaml)"
fi
if [[ -z "$VERSION" ]]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

# The version baked into Info.plist must be a plain x.y.z, but the artifact name
# may carry a suffix (1.0.0-abc1234) for non-release builds.
NUMERIC_VERSION="${VERSION%%-*}"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# ---------------------------------------------------------------------------
# Resolve the signing identity
# ---------------------------------------------------------------------------

if [[ "$FORCE_ADHOC" == true ]]; then
  IDENTITY=""
elif [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | sed -n 's/.*"\(.*\)"/\1/p' || true)"
fi

if [[ -n "$IDENTITY" ]]; then
  SIGN_MODE="developer-id"
  # Hardened runtime and a secure timestamp are both prerequisites for
  # notarization; a Developer ID signature without them is rejected.
  SIGN_ARGS=(--sign "$IDENTITY" --options runtime --timestamp)
else
  SIGN_MODE="adhoc"
  IDENTITY="-"
  # Ad-hoc signatures cannot be timestamped and cannot use the hardened runtime.
  SIGN_ARGS=(--sign - --timestamp=none)
fi

# ---------------------------------------------------------------------------
# Resolve notarization credentials
# ---------------------------------------------------------------------------

NOTARY_ARGS=()
NOTARIZE=false
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  NOTARIZE=true
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
  NOTARIZE=true
fi

case "$NOTARIZE_MODE" in
  never) NOTARIZE=false ;;
  always)
    if [[ "$SIGN_MODE" != "developer-id" ]]; then
      echo "--notarize requires a Developer ID identity; found none." >&2
      exit 1
    fi
    if [[ "$NOTARIZE" != true ]]; then
      echo "--notarize requires APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID (or NOTARY_KEYCHAIN_PROFILE)." >&2
      exit 1
    fi
    ;;
esac
# Apple only notarizes Developer ID signed code.
[[ "$SIGN_MODE" == "developer-id" ]] || NOTARIZE=false

# Submit a path to Apple, wait for the verdict, then attach the ticket so the
# artifact also validates on a Mac that is offline the first time it opens it.
# The staple target can differ from the submitted one: notarytool only accepts
# zip/dmg/pkg, while a ticket has to be stapled onto the bundle itself.
notarize_and_staple() {
  local submit_target="$1"
  local staple_target="${2:-$1}"
  echo "==> Notarizing $(basename "$submit_target") (this waits on Apple, usually 1-5 min)"
  xcrun notarytool submit "$submit_target" "${NOTARY_ARGS[@]}" --wait --timeout 30m
  echo "==> Stapling $(basename "$staple_target")"
  xcrun stapler staple "$staple_target"
}

echo "==> Building $APP_NAME $VERSION"
echo "    signing: $SIGN_MODE${SIGN_MODE:+ ($IDENTITY)}"
echo "    notarize: $NOTARIZE"

if [[ "$SKIP_BUILD" == false ]]; then
  "${FLUTTER[@]}" build macos --release --build-name="$NUMERIC_VERSION"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Sign the bundle
# ---------------------------------------------------------------------------

# Frameworks first, then the bundle — signing the outer bundle invalidates
# nested code that is signed afterwards. (`--deep` would do this in one step but
# is deprecated and signs nested code with the wrong entitlements.)
echo "==> Signing app bundle"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force "${SIGN_ARGS[@]}" "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" -print0)

  while IFS= read -r -d '' dylib; do
    codesign --force "${SIGN_ARGS[@]}" "$dylib"
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -name "*.dylib" -print0)
fi

codesign --force "${SIGN_ARGS[@]}" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

codesign --verify --strict --verbose=2 "$APP_PATH"

# ---------------------------------------------------------------------------
# Notarize the app itself
# ---------------------------------------------------------------------------

# The app is notarized before packaging so the copy the user drags into
# /Applications carries its own ticket. Notarizing only the DMG leaves the
# installed app dependent on an online Gatekeeper check.
if [[ "$NOTARIZE" == true ]]; then
  ZIP_DIR="$(mktemp -d)"
  APP_ZIP="$ZIP_DIR/$APP_NAME.zip"
  # ditto, not zip: it is the only archiver that preserves the symlinks and
  # extended attributes inside a bundle, which a signature depends on.
  ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  notarize_and_staple "$APP_ZIP" "$APP_PATH"
  rm -rf "$ZIP_DIR"
fi

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------

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

if [[ "$SIGN_MODE" == "developer-id" ]]; then
  echo "==> Signing disk image"
  codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
fi

# The DMG is notarized in its own right so the download itself passes Gatekeeper
# rather than only the app inside it.
if [[ "$NOTARIZE" == true ]]; then
  notarize_and_staple "$DMG_PATH"
  echo "==> Verifying Gatekeeper acceptance"
  spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
fi

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"

echo ""
echo "Done: $DMG_PATH ($SIZE)"
echo ""

if [[ "$NOTARIZE" == true ]]; then
  cat <<EOF
Signed with "$IDENTITY" and notarized. It opens on any Mac with a
double-click — no Gatekeeper prompt.
EOF
elif [[ "$SIGN_MODE" == "developer-id" ]]; then
  cat <<EOF
Signed with "$IDENTITY" but NOT notarized, so macOS still shows a
Gatekeeper warning on first launch. Set APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD
and APPLE_TEAM_ID to notarize.
EOF
else
  cat <<EOF
This DMG is ad-hoc signed and unnotarized, so macOS quarantines it after
download. To open it on another Mac:

  1. Drag $APP_NAME to Applications, then open System Settings ->
     Privacy & Security and choose "Open Anyway", or
  2. Run: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app
EOF
fi

cat <<EOF

$APP_NAME runs outside the App Sandbox (it has to, in order to inspect
/Applications and ~/Library). Grant Full Disk Access in System Settings, then
reopen the app — macOS caches the decision per process, so the grant does not
take effect until relaunch.
EOF

if [[ "$OPEN_AFTER" == true ]]; then
  open -R "$DMG_PATH"
fi
