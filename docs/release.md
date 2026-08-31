# Releasing Tidy

Tidy updates itself. The app asks GitHub once a day whether a newer release
exists, downloads the zip, checks it, and swaps itself out. That only works if
every release is built the same way, so this is the procedure.

`scripts/release.sh` does all of it. This document is what the script cannot
tell you: what to set up once, what the updater expects of a release, and the
two things that will bite on the first signed build

## One-time setup

### 1. A Developer ID Application certificate

Xcode → Settings → Accounts → your team → Manage Certificates → **+** →
**Developer ID Application**. This needs a paid Apple Developer Program
membership and the Account Holder or Admin role.

```
security find-identity -v -p codesigning
```

must list `Developer ID Application: … (ZJP8787K3Q)`. An *Apple Development*
certificate is not the same thing and cannot notarise.

A team gets at most five Developer ID certificates ever. Export the `.p12` and
back it up rather than creating one per machine.

**This is not optional, and not merely for Gatekeeper.** The updater verifies a
download against the *designated requirement of the copy already running*. An
ad-hoc signature's designated requirement is a hash of that one binary, which no
future build can ever match — so an ad-hoc build has nothing to check an update
against, and refuses to install one unless it can verify the checksum instead.

### 2. A notarytool keychain profile

```
xcrun notarytool store-credentials "tidy-notary" \
  --apple-id "you@example.com" \
  --team-id ZJP8787K3Q \
  --password "<app-specific password>"
```

The password comes from appleid.apple.com → Sign-In and Security → App-Specific
Passwords. It is **not** your Apple ID password.

### 3. `gh`, authenticated

Only needed for `--publish`.

## Cutting a release

1. Bump `version:` in `pubspec.yaml` — both halves. The name half is the version
   users see and the one the updater compares; the build half goes into
   `CFBundleVersion`.
2. Write the notes in `dist/RELEASE_NOTES.md`. The script writes a stub if there
   is none.
3. Commit. `--publish` refuses to run on a dirty tree.
4. ```
   ./scripts/release.sh --publish
   ```

That builds, signs, notarises, staples, packages, and creates the GitHub release
tagged `v<version>` with the zip, the DMG and `SHA256SUMS.txt` attached.

To rehearse without publishing, drop `--publish`. To rehearse without waiting on
Apple, add `--skip-notarize` — those artifacts are for local inspection only and
will not launch cleanly on another Mac.

## What the updater expects of a release

`lib/core/updates/github_release_client.dart` reads
`GET /repos/yunweneric/tidy/releases/latest` and needs:

| | |
|---|---|
| **Tag** | `v1.2.3` or `1.2.3`. A tag it cannot parse as three numbers is ignored, so the release is invisible to the updater. |
| **The zip** | An asset named `Tidy-<version>-macos.zip`. It falls back to the first `.zip` in the release, but do not rely on that. |
| **`SHA256SUMS.txt`** | Optional but published anyway. GitHub only records an asset `digest` for recent uploads, so this is the dependable source of the checksum. |
| **The DMG** | Optional. Offered as the manual route when the app cannot replace itself in place. |
| **Draft** | Ignored entirely. |
| **Prerelease** | Invisible unless the app was built with `--dart-define=TIDY_UPDATE_PRERELEASE=true`. |

To rehearse the whole flow against a scratch repository, build with
`--dart-define=TIDY_UPDATE_REPO=<owner>/<repo>`.

## Two things that will bite

### The first signed release costs every existing user their Full Disk Access

TCC keys a grant to the bundle id **and the code signature**. Today's builds are
ad-hoc signed, so their designated requirement is a hash of that exact binary.
The first Developer ID build cannot satisfy it, macOS treats it as a different
app, and the grant is gone — silently, because there is no prompt for Full Disk
Access. System Settings often still *shows* Tidy as enabled while denying it, so
users have to remove Tidy from the list and add it back.

**Say this in the release notes for the first signed build.** The same one-time
break hits the login-item registration: `SMAppService` will report the app as
not registered and the switch in Settings → General has to be flipped once.

Every release after that keeps the grant, including across certificate renewal —
the designated requirement names the team's OU, not a specific certificate.

### You cannot test the updater until two signed releases exist

`prepareUpdate` checks the download against the running app's signature, so
testing it against a locally built ad-hoc "update" fails by design and tells you
nothing. Plan for it: ship the first signed build, then immediately ship a second
whose only purpose is to be the target of the first real self-update.

## Why the hardened runtime is not set in the Xcode project

Notarisation requires the hardened runtime, and `release.sh` applies it at
signing time with `--options runtime`, which is what the check actually reads.

It is deliberately **not** set as `ENABLE_HARDENED_RUNTIME` in
`project.pbxproj`, and that was measured rather than assumed. With the hardened
runtime on, library validation requires every loaded framework to carry the same
Team ID as the process. An ad-hoc signature has no Team ID at all, so a locally
built Release app fails to load `FlutterMacOS.framework` and dies in `dyld`
before reaching `main`:

```
Library not loaded: @rpath/FlutterMacOS.framework/…
Reason: … mapping process and mapped file (non-platform) have different Team IDs
```

Setting it in the project would therefore break every local Release build and
`scripts/build_dmg.sh` along with it, to no benefit — `release.sh` re-signs both
frameworks with the Developer ID, so the Team IDs match there and the runtime is
applied where it counts.

For the same reason Release carries **no** hardened-runtime exceptions.
`com.apple.security.cs.allow-jit` is a Debug and Profile concern — a release
build is AOT — and `disable-library-validation` is unnecessary because every
framework in the bundle is signed by us. Add either only in response to a
concrete failure, never speculatively.

## Local ad-hoc builds

`scripts/build_dmg.sh` is unchanged and is still the right tool for a quick
unsigned DMG to hand to someone. It does not notarise, so macOS quarantines the
result, and the app it produces cannot install updates.
