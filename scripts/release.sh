#!/usr/bin/env bash
#
# Builds, signs, notarises, staples and publishes a Tidy release.
#
# Produces in dist/:
#   Tidy-<v>-macos.zip   the stapled app — what the in-app updater downloads
#   Tidy-<v>.dmg         the drag-to-install image — for a first, manual install
#   SHA256SUMS.txt       digests of both
#
# One-time setup on this machine:
#
#   1. A "Developer ID Application" certificate in the login keychain.
#      Xcode > Settings > Accounts > <team> > Manage Certificates > + >
#      Developer ID Application. Needs a paid Apple Developer Program
#      membership and the Account Holder role. A team gets at most five of
#      these ever, so export the .p12 and back it up rather than making one
#      per laptop.  Check with:  security find-identity -v -p codesigning
#
#   2. A notarytool keychain profile:
#      xcrun notarytool store-credentials "tidy-notary" \
#        --apple-id "you@example.com" --team-id ZJP8787K3Q \
#        --password "<app-specific password from appleid.apple.com>"
#      That is an app-specific password, NOT the Apple ID password.
#
#   3. gh, authenticated, if you pass --publish.
#
# Usage:
#   ./scripts/release.sh                 build, sign, notarise, staple
#   ./scripts/release.sh --publish       ... and create the GitHub release
#   ./scripts/release.sh --skip-build    package what is already built
#   ./scripts/release.sh --skip-notarize sign only — local smoke test, and the
#                                        artefacts are NOT shippable
#
# scripts/build_dmg.sh still exists and is still the right tool for a quick
# ad-hoc local build. This is the signed path.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Tidy"
TEAM_ID="ZJP8787K3Q"
GH_REPO="yunweneric/tidy"
KEYCHAIN_PROFILE="${TIDY_NOTARY_PROFILE:-tidy-notary}"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
ENTITLEMENTS="macos/Runner/Release.entitlements"

SKIP_BUILD=false
SKIP_NOTARIZE=false
PUBLISH=false
for arg in "$@"; do
  case "$arg" in
    --skip-build)    SKIP_BUILD=true ;;
    --skip-notarize) SKIP_NOTARIZE=true ;;
    --publish)       PUBLISH=true ;;
    -h|--help)       sed -n '2,37p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ─── Preflight ───────────────────────────────────────────────────────────────
# Each of these otherwise fails minutes into a build, and the notarisation one
# costs a round trip to Apple to discover.

IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n "s/.*\"\(Developer ID Application: .*(${TEAM_ID})\)\".*/\1/p" | head -1)"
if [[ -z "$IDENTITY" ]]; then
  cat >&2 <<MSG
No "Developer ID Application" certificate for team $TEAM_ID in the keychain.

That certificate is what makes an update verifiable: the app checks a download
against the signature of the copy already running, and an ad-hoc signature has
nothing to check against. See the one-time setup at the top of this script.
MSG
  exit 1
fi
echo "==> Signing as: $IDENTITY"

if [[ "$SKIP_NOTARIZE" == false ]]; then
  if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" --limit 1 >/dev/null 2>&1; then
    echo "notarytool keychain profile '$KEYCHAIN_PROFILE' is missing or invalid." >&2
    echo "See the one-time setup at the top of this script." >&2
    exit 1
  fi
fi

VERSION="$(awk '/^version:/ { split($2, v, "+"); print v[1]; exit }' pubspec.yaml)"
BUILD_NUMBER="$(awk '/^version:/ { split($2, v, "+"); print v[2]; exit }' pubspec.yaml)"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || {
  echo "Could not read version from pubspec.yaml" >&2; exit 1; }
TAG="v$VERSION"

if [[ "$PUBLISH" == true ]]; then
  command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated" >&2; exit 1; }
  [[ -z "$(git status --porcelain)" ]] || {
    echo "Working tree is dirty; commit before releasing." >&2; exit 1; }
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists. Bump 'version:' in pubspec.yaml." >&2
    exit 1
  fi
fi

ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macos.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
SUBMIT_ZIP="$DIST_DIR/.$APP_NAME-$VERSION-submit.zip"

# ─── Build ───────────────────────────────────────────────────────────────────
# xcodebuild directly rather than `flutter build macos`. The wrapper fails on
# some machines at destination resolution — it asks for arm64 while xcodebuild
# reports only an x86_64 destination — and this invocation still runs Flutter's
# own xcode_backend.sh build phase, so the bundle it produces is complete.

echo "==> Building $APP_NAME $VERSION+$BUILD_NUMBER"
if [[ "$SKIP_BUILD" == false ]]; then
  flutter pub get
  xcrun xcodebuild \
    -workspace macos/Runner.xcworkspace \
    -configuration Release \
    -scheme Runner \
    -derivedDataPath build/macos \
    -destination "platform=macOS,arch=arm64" \
    OBJROOT="$PWD/build/macos/Build/Intermediates.noindex" \
    SYMROOT="$PWD/build/macos/Build/Products" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build
fi
[[ -d "$APP_PATH" ]] || { echo "No app bundle at $APP_PATH" >&2; exit 1; }

# The bundle is the source of truth for what the release will claim. A stale
# ephemeral xcconfig is enough to make these disagree, and the updater's own
# "is this newer" check would then reject the release it just published.
BUILT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "pubspec says $VERSION but the built bundle says $BUILT_VERSION." >&2
  echo "Run 'flutter clean' and build again." >&2
  exit 1
fi

# ─── Sign ────────────────────────────────────────────────────────────────────
# Inside out. Signing the outer bundle seals everything under it, so anything
# signed afterwards invalidates the seal. `--deep` would do this in one step but
# is deprecated for signing and applies the app's entitlements to nested code,
# which notarisation rejects.
#
# --timestamp is not optional: without a secure timestamp the signature stops
# being valid the day the certificate expires, and notarisation refuses it
# outright. --options runtime is the hardened runtime, which notarisation
# requires on every executable in the bundle, not just the main one.

echo "==> Signing"
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

FRAMEWORKS="$APP_PATH/Contents/Frameworks"
if [[ -d "$FRAMEWORKS" ]]; then
  # Loose Mach-O first: a dylib inside a framework has to be signed before the
  # framework that seals it.
  while IFS= read -r -d '' dylib; do
    sign "$dylib"
  done < <(find "$FRAMEWORKS" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)

  # Then each framework — Versions/A rather than the .framework, because that is
  # the directory codesign actually seals.
  for framework in "$FRAMEWORKS"/*.framework; do
    [[ -e "$framework" ]] || continue
    if [[ -d "$framework/Versions/A" ]]; then
      sign "$framework/Versions/A"
    else
      sign "$framework"
    fi
  done
fi

# Helper apps and XPC services. None today, but a plugin adds them without
# announcing it, and an unsigned one is a notarisation rejection discovered two
# minutes before you wanted to ship.
while IFS= read -r -d '' nested; do
  sign "$nested"
done < <(find "$APP_PATH/Contents" -mindepth 2 -type d \( -name '*.xpc' -o -name '*.app' \) -print0)

# The app last, and the only thing that carries entitlements — nested code
# carrying the app's entitlements is a rejection.
sign --entitlements "$ENTITLEMENTS" "$APP_PATH"

echo "==> Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# flags= must contain (runtime); TeamIdentifier must be the team above.
codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
  | grep -E 'Identifier=|TeamIdentifier=|flags=|^Authority'

mkdir -p "$DIST_DIR"

# ─── Notarise ────────────────────────────────────────────────────────────────

notarize() {
  local artifact="$1" label="$2" response status id
  echo "==> Notarising $label — Apple usually takes 1-5 minutes"
  response="$(xcrun notarytool submit "$artifact" \
    --keychain-profile "$KEYCHAIN_PROFILE" --wait --timeout 30m \
    --output-format json)" || true
  status="$(printf '%s' "$response" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$response" | plutil -extract id raw -o - - 2>/dev/null || true)"

  if [[ "$status" != "Accepted" ]]; then
    echo "Notarisation returned '${status:-no status}'." >&2
    # Without this you get a one-word verdict and no idea which binary was the
    # problem. The log names the file and the reason.
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$KEYCHAIN_PROFILE" >&2
    exit 1
  fi
}

if [[ "$SKIP_NOTARIZE" == false ]]; then
  echo "==> Packing for submission"
  rm -f "$SUBMIT_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMIT_ZIP"
  notarize "$SUBMIT_ZIP" "$APP_NAME.app"

  # Stapling writes the ticket into the bundle, outside the sealed directory, so
  # it does not invalidate the signature. Without it Gatekeeper has to ask Apple
  # over the network on first launch, and a user who is offline — or behind a
  # firewall that blocks Apple's service — sees "Tidy is damaged".
  echo "==> Stapling"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$SUBMIT_ZIP"
fi

# ─── The shipping zip ────────────────────────────────────────────────────────
# Built AFTER stapling, from the stapled bundle, and a different file from the
# one submitted above. Shipping the submission zip by mistake is the single most
# common way a correctly notarised release still fails on users' machines: it
# works everywhere with a network and fails everywhere without one.

echo "==> Building $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# ─── The DMG ─────────────────────────────────────────────────────────────────

echo "==> Building $DMG_PATH"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
# ditto rather than cp -R: the staged copy has to keep the signature and the
# stapled ticket.
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -ov -quiet "$DMG_PATH"
hdiutil verify -quiet "$DMG_PATH"

# A DMG is signed as a flat file: no entitlements, no runtime option.
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == false ]]; then
  notarize "$DMG_PATH" "$(basename "$DMG_PATH")"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  echo "==> Gatekeeper assessment"
  # Must print: accepted / source=Notarized Developer ID
  spctl --assess --verbose=4 --type execute "$APP_PATH"
  # A DMG is assessed as a document being opened, against its primary signature.
  spctl --assess --verbose=4 --type open \
    --context context:primary-signature "$DMG_PATH"
fi

# ─── Digests ─────────────────────────────────────────────────────────────────

ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
DMG_SHA="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
{
  echo "$ZIP_SHA  $(basename "$ZIP_PATH")"
  echo "$DMG_SHA  $(basename "$DMG_PATH")"
} > "$DIST_DIR/SHA256SUMS.txt"

NOTES_FILE="$DIST_DIR/RELEASE_NOTES.md"
if [[ ! -f "$NOTES_FILE" ]]; then
  printf '## %s\n\n- \n' "$VERSION" > "$NOTES_FILE"
  echo "Wrote a stub at $NOTES_FILE — fill it in before publishing."
fi

# ─── Publish ─────────────────────────────────────────────────────────────────
# The updater finds the zip by name (Tidy-*-macos.zip) and reads the SHA-256
# GitHub records for it, so the asset name matters. See docs/release.md.

if [[ "$PUBLISH" == true ]]; then
  echo "==> Creating GitHub release $TAG"
  gh release create "$TAG" \
    --repo "$GH_REPO" \
    --title "$APP_NAME $VERSION" \
    --notes-file "$NOTES_FILE" \
    --target "$(git rev-parse --abbrev-ref HEAD)" \
    "$ZIP_PATH" "$DMG_PATH" "$DIST_DIR/SHA256SUMS.txt"
fi

cat <<EOF

Done.

  $ZIP_PATH
    $ZIP_SHA
  $DMG_PATH
    $DMG_SHA

EOF

if [[ "$SKIP_NOTARIZE" == true ]]; then
  echo "NOT NOTARISED — these artefacts are for local testing only." >&2
fi
