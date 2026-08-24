# CI / CD

One workflow, `ci.yml`, driven by the Flutter version pinned in `.fvmrc`. It
runs on pushes to `main`, PRs into `main`, `v*` tags, and manual dispatch:

| Job | Runner | Does |
| --- | --- | --- |
| `prepare` | ubuntu | Resolves the artifact version and the Flutter SDK version |
| `verify` | ubuntu | `dart format` check, `flutter analyze`, `flutter test` (skipped while there is no `test/`) |
| `build-macos` | macOS | Builds, Developer ID signs, notarizes, staples, packages the DMG, uploads it as an artifact |
| `release` | ubuntu | Tags only: checksums the DMG and publishes a GitHub Release |
| `summary` | ubuntu | Writes signing/notarization status into the run summary |

Lint and build live in one workflow so a tag can never publish code that did
not pass analysis.

Tidy is macOS-only, so there is no Windows/Linux/Android leg. The `android/`,
`linux/` and `windows/` directories are leftovers from `flutter create` and are
not built.

## Cutting a release

```bash
# bump `version:` in pubspec.yaml first
git tag v1.0.0
git push origin v1.0.0
```

The tag name is the artifact version (`v1.0.0` → `Tidy-1.0.0.dmg`). Builds off
`main` are versioned `<pubspec version>-<short sha>` and only upload an
artifact — they never publish a Release.

## Signing secrets

Without these, the workflow still succeeds: it falls back to an **ad-hoc signed**
DMG and says so in the run summary and the release notes. Add all six to get a
DMG that opens with a double-click on any Mac.

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64 of the exported **Developer ID Application** `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `APPLE_ID` | Apple ID that owns the developer account (`yunweneric@gmail.com`) |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | `ZJP8787K3Q` |

Add them under **Settings → Secrets and variables → Actions → New repository
secret**, or from the CLI:

```bash
gh secret set MACOS_CERTIFICATE < certificate.b64
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
gh secret set APPLE_TEAM_ID
```

### 1. Get a Developer ID Application certificate

Requires a paid **Apple Developer Program** membership ($99/year) — a free
Apple ID only issues "Apple Development" certificates, which cannot sign apps
for distribution and cannot be notarized.

1. <https://developer.apple.com/account/resources/certificates/list> →
   **+** → **Developer ID Application** → *Previous Sub-CA is not needed*.
2. Upload a CSR (Keychain Access → Certificate Assistant → *Request a
   Certificate From a Certificate Authority*, "Saved to disk").
3. Download the `.cer` and double-click it to install into the login keychain.

Verify it landed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# 1) ABC…  "Developer ID Application: Yunwen Eric (ZJP8787K3Q)"
```

### 2. Export it for CI

Keychain Access → **My Certificates** → right-click *Developer ID Application:
Yunwen Eric* → **Export** → `.p12`, with a password. Then:

```bash
base64 -i Certificates.p12 -o certificate.b64
gh secret set MACOS_CERTIFICATE < certificate.b64
rm certificate.b64 Certificates.p12   # never commit either
```

Export the certificate *row* (which carries the private key), not the key on
its own — a `.p12` without the private key cannot sign.

### 3. App-specific password for notarization

<https://account.apple.com> → **Sign-In and Security** → **App-Specific
Passwords** → **+**. This is not the Apple ID password; the account password
will not authenticate `notarytool`.

## Building locally

`scripts/build_dmg.sh` is the same code path CI uses, so a local run reproduces
the release artifact:

```bash
./scripts/build_dmg.sh            # ad-hoc signs unless a Developer ID cert is installed
./scripts/build_dmg.sh --adhoc    # force ad-hoc, ignoring an installed cert
./scripts/build_dmg.sh --help
```

With the certificate in your keychain it is picked up automatically. To also
notarize, export the same three values the workflow uses:

```bash
export APPLE_ID=yunweneric@gmail.com
export APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
export APPLE_TEAM_ID=ZJP8787K3Q
./scripts/build_dmg.sh --notarize
```

Or, to keep the password out of your shell history, store it once and use the
profile instead:

```bash
xcrun notarytool store-credentials tidy \
  --apple-id yunweneric@gmail.com --team-id ZJP8787K3Q
NOTARY_KEYCHAIN_PROFILE=tidy ./scripts/build_dmg.sh --notarize
```

## Troubleshooting

**`errSecInternalComponent` when codesign runs on CI** — the keychain locked
mid-build or `set-key-partition-list` did not run. Both are handled in the
import step; if it reappears, check that the `.p12` was exported with its
private key.

**Notarization returns `Invalid`** — fetch the reason, it is never in the
summary line:

```bash
xcrun notarytool log <submission-id> --apple-id … --team-id … --password …
```

The usual causes are a missing hardened runtime (`--options runtime`) or an
unsigned nested binary. `scripts/build_dmg.sh` sets both, so this normally
means a new bundled dylib is not being reached by the signing loop.

**Gatekeeper still warns after notarization** — the ticket was not stapled, or
the download carries a quarantine flag from an older copy. Check with:

```bash
xcrun stapler validate Tidy-1.0.0.dmg
spctl --assess --type open --context context:primary-signature -vv Tidy-1.0.0.dmg
```
