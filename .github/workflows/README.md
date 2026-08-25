# CI / CD

Two workflows, both driven by the Flutter version pinned in `.fvmrc`: `ci.yml`
builds and releases the macOS app, and `pages.yml` deploys the landing page.

## `ci.yml` — the app

Runs on pushes to `main`, PRs into `main`, `v*` tags, and manual dispatch:

| Job | Runner | Does |
| --- | --- | --- |
| `prepare` | ubuntu | Resolves the artifact version and the Flutter SDK version |
| `verify` | ubuntu | `dart format` check, `flutter analyze`, `flutter test` (skipped while there is no `test/`) |
| `build-macos` | macOS | Runs `scripts/build_dmg.sh --zip`, checksums the output, uploads it as an artifact |
| `release` | ubuntu | Tags only: publishes a GitHub Release with both artifacts and `SHA256SUMS.txt` |
| `summary` | ubuntu | Writes the version and build result into the run summary |

Lint and build live in one workflow so a tag can never publish code that did
not pass analysis.

Tidy is macOS-only, so there is no Windows/Linux/Android leg. The `android/`,
`linux/` and `windows/` directories are leftovers from `flutter create` and are
not built.

## Builds are unsigned

CI produces exactly what `scripts/build_dmg.sh` produces on a developer's Mac:
an **ad-hoc signed** app, not signed with a Developer ID and not notarized.
That is a deliberate choice — Developer ID signing needs a paid Apple Developer
Program membership — and it has two consequences worth knowing:

- **Gatekeeper blocks the first launch.** The release notes tell downloaders to
  open System Settings → Privacy & Security and choose *Open Anyway*. The
  release notes are generated, so this stays accurate without anyone
  remembering to write it.
- **The in-app updater falls back to checksum verification.** It normally
  checks that an update is signed by whoever signed the running copy; an ad-hoc
  signature's designated requirement is a hash of one specific binary, so no
  future build can satisfy it. What it verifies instead is the SHA-256 digest
  from `SHA256SUMS.txt`, which is why the checksum step is not optional —
  without that asset an unsigned release has no integrity check at all and the
  updater will refuse it. See [docs/release.md](../../docs/release.md).

No secrets are required. Nothing in this workflow talks to Apple.

## Cutting a release

```bash
# bump `version:` in pubspec.yaml first — the tag must match it
git tag v1.0.0
git push origin v1.0.0
```

`prepare` fails the run if the tag and the pubspec version disagree. They have
to match because the updater compares the release tag against the running app's
`CFBundleShortVersionString`, which comes from pubspec — a mismatch means users
either never see the update or are offered one they already have.

The release carries three assets:

| Asset | Purpose |
| --- | --- |
| `Tidy-<version>-macos.zip` | What the in-app updater downloads. It finds it by this exact name. |
| `Tidy-<version>.dmg` | The drag-to-install image, for a first manual install |
| `SHA256SUMS.txt` | Digests of both — the updater's integrity check |

Builds off `main` and from PRs use the version `<pubspec version>-<short sha>`
and only upload an artifact; they never publish a Release.

## Building locally

`scripts/build_dmg.sh` is the same code path CI uses, so a local run reproduces
the release artifacts:

```bash
./scripts/build_dmg.sh          # dist/Tidy-<version>.dmg
./scripts/build_dmg.sh --zip    # ... and Tidy-<version>-macos.zip
./scripts/build_dmg.sh --help
```

## Troubleshooting

**The macOS job fails in `xcodebuild` but a local build works** — the runner
starts from a clean checkout, where `macos/Pods` and `macos/Flutter/ephemeral`
do not exist yet. `build_dmg.sh` runs `flutter build macos --config-only` to
generate both before calling `xcodebuild`; if that step is skipped (via
`--skip-build`) on a fresh checkout, the workspace will not resolve.

**`Verify formatting` fails and nothing else ran** — the format check gates the
job, so analyze and tests never start. Run `dart format .`, commit, push. To
catch it before the push instead, install the repo's hooks once:
`git config core.hooksPath scripts/hooks`.

**A release published but the app never offers the update** — check, in order:
the tag parses as three numbers, the release is not a draft, it is not marked
prerelease (invisible unless the app was built with
`--dart-define=TIDY_UPDATE_PRERELEASE=true`), and the zip is named
`Tidy-<version>-macos.zip`.

## `pages.yml` — the landing page

Builds `lib/main_landing.dart` for the web and publishes it to GitHub Pages at
[tidy.yunweneric.com](https://tidy.yunweneric.com), through
`actions/upload-pages-artifact` + `actions/deploy-pages` — the official route,
not a `gh-pages` branch.

| Job | Runner | Does |
| --- | --- | --- |
| `build` | ubuntu | Resolves the SDK and the base href, analyzes `lib/landing`, `flutter build web` |
| `deploy` | ubuntu | Publishes the artifact to the `github-pages` environment |

It triggers only on pushes to `main` that touch what it actually compiles:
`lib/landing/**`, `lib/main_landing.dart`, `web/**`, `pubspec.yaml`, this
workflow — and `lib/core/**`, `lib/features/shell/domain/**` and
`lib/features/menubar/presentation/widgets/**`, because the page is built out
of the app's own tokens, components, navigation model and popover rows.

Three details that matter:

- **The base href is derived, not hard-coded.** A custom domain serves from `/`;
  a bare project page serves from `/<repo>/`. Getting it wrong 404s every asset
  including `flutter_bootstrap.js`, which leaves the page stuck on its boot
  curtain with no error anywhere. The step reads `web/CNAME` and picks. Delete
  that file and the site falls back to `yunweneric.github.io/tidy` correctly.
- **`--wasm`.** Compiles to WasmGC and renders with skwasm, emitting the
  dart2js + CanvasKit build alongside it as the fallback; `flutter.js` picks
  per browser. Roughly 2.2 MB gzipped on the wasm path against 3.4 MB on the
  JavaScript one, and noticeably smoother to scroll.
- **`--pwa-strategy none`.** No service worker. A marketing page must never
  serve a cached previous version after a deploy.
- **`flutter analyze` is scoped to `lib/landing` and `lib/main_landing.dart`.**
  This bundle does not contain the product — no platform channels, no Hive
  store, no updater — and a failure in code it never compiles should not stop
  the site deploying. `ci.yml` analyzes the whole tree.

### Repository settings this needs

Once, by hand: **Settings → Pages → Source → GitHub Actions**, and **Settings →
Pages → Custom domain → `tidy.yunweneric.com`** with *Enforce HTTPS* on. DNS
side: a `CNAME` record for `tidy` pointing at `yunweneric.github.io`.
