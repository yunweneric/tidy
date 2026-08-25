# Tidy

A Mac utility toolkit. One app for the small jobs macOS makes awkward — clipboard
history, disk cleanup, uninstalling apps properly, startup and process control,
and getting things back out of the Trash.

It started as an uninstaller. That is still in here, but it is one module of
several now.

**[tidy.yunweneric.com](https://tidy.yunweneric.com)** — the landing page, with
the app itself running in it on invented data. It is this repository compiled
for the web from `lib/main_landing.dart`; see [The landing page](#the-landing-page).

## What's in it

| Module | What it does | State |
|---|---|---|
| **Smart Care** | Runs every built check in one pass, reviewed in one place | ✅ Built |
| **Cleanup** | Caches, logs, saved window state, leftovers from apps that are gone | ✅ Built |
| **Clipboard** | Searchable copy history with pins, images and a `⌘⇧V` hotkey | ✅ Built |
| **Performance** | Login items, background agents, macOS maintenance, running processes | ✅ Built |
| **Applications** | Uninstall apps and everything they left behind | ✅ Built |
| **Recycle Bin** | Every trash on every volume, with working Put Back | ✅ Built |
| **Protection** | Known adware, suspicious launch agents, privacy traces | ⏳ Planned |
| **My Clutter** | Duplicates, similar photos, large and old files | ⏳ Planned |
| **Space Lens** | A map of what is actually using the disk | ⏳ Planned |
| **Network meter** | Live throughput, per-interface, in the menu bar | ⏳ Planned |

Planned modules are visible in the sidebar and say plainly that they are not
built yet. None of them show a scan button that finds nothing — a cleaner
reporting "0 threats found" from a scanner that does not exist is lying, and
this app does not do that.

## The menu bar

Click the icon for a popover with live vitals — CPU, memory, swap, thermal
state, uptime — plus reclaimable junk, Trash size, your recent clips, and what
is currently using the most CPU. Most of it is actionable without opening the
window.

The popover runs a **second Flutter engine**, so it works with the main window
closed. Closing the window leaves it running.

## Highlights

**Clipboard history lives natively.** The store is Swift, not Dart, for two
reasons: capture has to keep working with no window open, and with two Flutter
engines in separate isolates a Dart-side store would be two writers racing on
every copy. Each engine gets a channel onto the one native store.

The global hotkey uses Carbon's `RegisterEventHotKey` rather than an `NSEvent`
global monitor. The monitor route needs Accessibility permission and sees every
keystroke you type — a large thing to ask for one shortcut. This route asks for
nothing and only hears the combination it registered.

**Uninstalling shows you everything first.** Leftovers are matched by bundle id
(`com.acme.Widget`, `com.acme.Widget.plist`, `com.acme.Widget.helper.plist`) and
by exact display-name match across `~/Library` and `/Library` — never by
substring, which is how cleaners end up deleting `~/Library/Mail` because an app
was called "Mail". Every item is listed with its size and a checkbox before
anything is touched.

**Removal defaults to the Trash**, through `FileManager.trashItem`, so it is
recoverable and Put Back works. Permanent deletion is a deliberate switch.

**Nothing is pre-ticked unless it is genuinely safe.** Findings are graded
safe / review / risky, and only the first is selected for you. An inference
about what a file *probably* is — an orphan, an unused app — is never safe.

**Guarded natively.** The Swift layer refuses `/System`, volume roots, mount
points, `~/Library` and its standard subfolders, and the home directory,
regardless of what asks. It resolves symlinks before checking, so a link inside
an allowed folder cannot be used to reach a protected one.

**Honest accounting.** Sizes are what a file *occupies*, not its logical length —
on APFS a sparse file like `Docker.raw` reports 64 GB while using 8. Moving to
the Trash frees nothing until the Trash is emptied, and the app says "moved to
Trash" rather than claiming space back it has not returned yet.

Failures are reported per item rather than swallowed, so a leftover needing
administrator rights tells you so instead of appearing to succeed.

## Requirements

- macOS 11 or later
- Flutter — developed on **3.38.10**. Note `.fvmrc` pins `3.35.7`, which is not
  installed locally; either `fvm install 3.35.7` or update the pin.
- **Not sandboxed, and cannot be.** It reads `/Applications` and `~/Library`,
  walks the filesystem natively, and manages launch agents. That rules out Mac
  App Store distribution, which is why it ships as a DMG.
- **Full Disk Access** is optional but recommended. Without it some TCC-protected
  folders are skipped and scans under-report — the app tells you when that has
  happened rather than reporting a confident zero. There is a shortcut in the
  sidebar, and macOS requires a relaunch after granting it.

## Running from source

```bash
flutter pub get
flutter run -d macos
git config core.hooksPath scripts/hooks   # once per clone
```

That last line installs the repo's hooks. `scripts/hooks/pre-commit` runs the
same `dart format` check CI runs, against the staged content, and refuses a
commit that would fail the build — `git commit --no-verify` skips it. It is one
command rather than automatic because git will not let a repository install its
own hooks, and that is a good thing.

Test Full Disk Access from the **built** `.app`, not `flutter run` — TCC grants
are keyed to the bundle.

## Building and releasing

Two paths, for two different purposes.

**A quick unsigned build**, to hand to someone or to test packaging:

```bash
./scripts/build_dmg.sh          # release build, then package
./scripts/build_dmg.sh --open   # ... and reveal it in Finder
```

Produces `dist/Tidy-<version>.dmg`, ad-hoc signed. macOS quarantines it after
download, so on the target Mac open **System Settings → Privacy & Security** and
choose **Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Tidy.app
```

An app built this way can still update itself, but only against a published
checksum — see below.

**A real release**, signed with a Developer ID, notarized and published:

```bash
./scripts/release.sh --publish
```

That builds, signs the frameworks and the bundle under the hardened runtime,
notarizes and staples both artifacts, and creates the GitHub release tagged
`v<version>` with `Tidy-<version>-macos.zip`, `Tidy-<version>.dmg` and
`SHA256SUMS.txt` attached. It needs a Developer ID Application certificate and a
`notarytool` keychain profile — [docs/release.md](docs/release.md) covers the
one-time setup, what the updater expects of a release, and the two things that
bite on the first signed build.

**Unsigned releases from CI.** `.github/workflows/ci.yml` lints and builds every
push and PR, and on a `v*` tag publishes the zip, the DMG and `SHA256SUMS.txt`
to a GitHub Release. It runs `scripts/build_dmg.sh`, so what it ships is ad-hoc
signed and never notarized — Gatekeeper blocks the first launch, and the updater
verifies downloads against the published checksum instead of a code signature.
No Apple credentials are involved. See
[.github/workflows/README.md](.github/workflows/README.md).

## The landing page

[tidy.yunweneric.com](https://tidy.yunweneric.com) is this repository, compiled
for the web from a second entry point:

```
lib/main_landing.dart          the entry point — no DI, no router, no logging
lib/landing/
├── landing_app.dart           MaterialApp on TidyTheme.light() / .dark()
├── landing_page.dart          one scroll view, a floating bar, a scroll spy
├── state/                     LandingController — theme, release, anchors
├── data/                      the public GitHub releases API
├── sections/                  the page, band by band
├── widgets/                   Reveal, PointerTilt, ScrollTilt, GlassPanel, frames
└── preview/                   the app and the menu bar, on invented data
```

Run it with `flutter run -d chrome -t lib/main_landing.dart`, or the
**Landing page (Chrome)** configuration in `.vscode/launch.json`.

**The page imports the product.** Everything under `lib/core/design/` and
`lib/core/widgets/` is free of `dart:io` and free of the service locator, as are
`AppDestination` and `SidebarNavItem` — so the window in the middle of the page
is the app's own `AmbientBackground`, `TidyCard`, `StatTile`, `GaugeRing`,
`SparkChart` and `StackedBar`, handed constants instead of scan results. The
module grid is generated from `AppDestination`, blurbs included. Adding a module
adds a card; rewording a blurb rewords the page. A marketing site with its own
copy of the feature list is a marketing site that will eventually be wrong.

`lib/landing/preview/menu_bar_preview.dart` draws the menu bar and all three
popovers the same way — the status items, the pointer, the 460pt dashboard panel
and the two 320pt ones, at the widths `MenuBarController.swift` actually uses.

`lib/landing/preview/preview_mac.dart` is the fiction behind the demo — a 512 GB
disk, 66 apps, four junk categories, a Trash, a clipboard. It is a
`ChangeNotifier` rather than a wall of constants because the demo has to add up:
reclaiming junk puts it in the Recycle Bin pane, emptying the Trash is what
actually moves the free-space bar, and uninstalling an app is undoable from
another screen.

Do **not** import `core/platform/`, `core/store/`, `core/settings/`,
`core/updates/` or any feature's `logic/` or `data/` from `lib/landing/`. They
reach `dart:io`, which does not compile for web.

`.github/workflows/pages.yml` builds and publishes on every push to `main` that
touches the landing sources. `web/CNAME` is what tells it to build with
`--base-href /` rather than `/tidy/`; delete it and the workflow falls back to
the project page without any other change. `web/index.html` is hand-written —
the Open Graph head, the boot curtain and a `<noscript>` block are all a crawler
ever sees of a page that renders to a canvas — which is why
`flutter_native_splash` has `web: false`. Regenerate the social card with
`python3 scripts/generate_og_image.py`.

## Updating

Tidy updates itself, the way ChatGPT and Claude for Mac do. Once a day — and
shortly after launch — it asks GitHub whether a newer release exists. If there
is one, it says so; you press Download, watch it arrive, and press **Install and
Relaunch**. Settings → Updates has the controls, including the switch that turns
the check off.

That check is the only network request the app makes. It sends nothing but the
question.

Before anything is installed, the download is checked against the release
checksum, unpacked, confirmed to be Tidy and to be *newer*, and verified against
the code signature of the copy already running — an update has to be signed by
whoever signed what is installed. Then the two bundles are exchanged with a
single atomic `renamex_np(RENAME_SWAP)` and a detached helper reopens the app
once this one has exited.

An unsigned build cannot use that last check: an ad-hoc designated requirement
is a hash of one specific binary, so no future build could ever match it. There
the SHA-256 digest published with the release stands in its place, and becomes
mandatory — an unsigned build refuses an update that announces no checksum,
because that would be no verification at all.

## Project structure

```
lib/
  core/
    design/           Tokens, light + dark themes, icon registry, brand
    di/               get_it registrations
    platform/         Method channels: system, full disk access
    router/           go_router config — one branch per destination
    scanning/         The scan contract every module shares
      domain/           ScanModule, ScanNode, selection, composite
      logic/            ScanBloc
      presentation/     ScanView: scan → tiles → review → clean, written once
    settings/         Theme, reduce motion, onboarding state
    updates/          Check GitHub, download, hand off to the installer
    utils/            Batched sizing, byte formatting, concurrency pool
    widgets/          Shared components
  features/
    smart_care/       Composite scan over every built module
    cleanup/          Junk scanner as a ScanModule
    clipboard/        History, pins, search, preview
    performance/      Launch items, maintenance, process monitor
    apps/             Uninstaller, leftover preview, app inventory
    recycle_bin/      Trash bins across volumes, restore
    menubar/          The popover (second Flutter engine)
    onboarding/       First run, and the permission conversation
    settings/         Settings page
    shell/            Sidebar, destinations, window chrome
  landing/            The marketing site — see "The landing page" above
  main.dart           The app
  main_landing.dart   The site
macos/Runner/
  DirectorySizer.swift      fts(3) tree walk, allocated sizes
  SystemChannel.swift       FileManager removal, disk, icons, path guards
  FullDiskAccess.swift      TCC probe + System Settings deep link
  ClipboardChannel.swift    Native clipboard store, monitor, preview panel
  PerformanceChannel.swift  Launch items, maintenance, processes, vitals
  RecycleBinChannel.swift   Trash bins and Put Back
  MenuBarController.swift   NSStatusItem + NSPopover + second Flutter engine
  HotKey.swift              Carbon global shortcut
  UpdateChannel.swift       The updater's native surface
  Updater.swift             Verify a download, swap the bundle, relaunch
scripts/
  build_dmg.sh              Quick ad-hoc build → DMG
  release.sh                Build → Developer ID sign → notarize → publish
  add_swift_file.py         Register a Swift file with the Xcode target
  hooks/pre-commit          Format check on staged Dart, mirroring CI
  generate_icons.py         Regenerate the app icon and menu bar glyphs
  generate_og_image.py      Regenerate the landing page's social card
docs/
  feature.md                How to build a feature, and the safety rules
  ui.md                     Theming, tokens, components, copy
  release.md                Cutting a release, and what the updater expects
```

## Architecture

Most modules are **not screens**. A scanner implements `ScanModule`, returns a
tree of `ScanNode`s, and the generic `ScanView` renders the whole
scan → tiles → review → clean flow. Adding a scanner is a data source plus some
copy, not a new page. Smart Care takes this one step further — it is purely a
composite that fans out to the other modules and merges their results,
deduplicating paths two modules both claim.

Navigation is `go_router` with `StatefulShellRoute.indexedStack`, so every
destination is a real route whose state survives being navigated away from. That
matters here: a Cleanup sweep runs for tens of seconds, and losing it because
you glanced at another module would be its own bug.

Styling goes through tokens — no widget hard-codes a colour, size, radius,
duration or icon. That is what makes light mode and Reduce Motion work.

**Read [docs/feature.md](docs/feature.md) before adding a feature and
[docs/ui.md](docs/ui.md) before styling anything.** The safety rules in the first
one are not stylistic; this app deletes files.

## A note on names

Everything is `tidy` now — the Dart package, the repository, the folder and the
bundle id (`com.yunweneric.tidy`). The product name itself lives in
`lib/core/design/brand.dart`.

The rename was left until it was cheap. TCC grants — Full Disk Access in
particular — are keyed to the bundle id plus signing identity, so changing it
revokes them: anyone running the app has to grant access again. Doing it before
release meant the only install that paid was a developer's.

The Application Support folder moved from `MacUninstaller` to `Tidy` at the same
time. `macos/Runner/AppSupport.swift` moves it on first launch, before anything
reads it, so settings, the scan cache, the trash ledger behind Recycle Bin's
"Put Back" and the clipboard history all survive rather than being orphaned
beside a fresh empty folder.

## License

GPL-3.0. See [LICENSE](LICENSE).

Copyleft rather than permissive, and for one reason: this app asks for Full
Disk Access and then walks your Library. The argument for trusting it is that
you can read what it does, and a modified Tidy has to keep that argument
available to whoever runs *it*.
