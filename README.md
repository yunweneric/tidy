# Tidy

A Mac utility toolkit. One app for the small jobs macOS makes awkward — clipboard
history, disk cleanup, uninstalling apps properly, startup and process control,
and getting things back out of the Trash.

It started as an uninstaller. That is still in here, but it is one module of
several now.

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
```

Test Full Disk Access from the **built** `.app`, not `flutter run` — TCC grants
are keyed to the bundle.

## Building a DMG

```bash
./scripts/build_dmg.sh          # release build, then package
./scripts/build_dmg.sh --open   # ... and reveal it in Finder
```

Produces `dist/Tidy-<version>.dmg`. The app is ad-hoc signed
(`codesign --sign -`), not Developer ID signed and not notarized, so macOS
quarantines it after download. On the target Mac either right-click and choose
**Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Tidy.app
```

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
macos/Runner/
  DirectorySizer.swift      fts(3) tree walk, allocated sizes
  SystemChannel.swift       FileManager removal, disk, icons, path guards
  FullDiskAccess.swift      TCC probe + System Settings deep link
  ClipboardChannel.swift    Native clipboard store, monitor, preview panel
  PerformanceChannel.swift  Launch items, maintenance, processes, vitals
  RecycleBinChannel.swift   Trash bins and Put Back
  MenuBarController.swift   NSStatusItem + NSPopover + second Flutter engine
  HotKey.swift              Carbon global shortcut
scripts/
  build_dmg.sh              Release build → ad-hoc sign → DMG
  add_swift_file.py         Register a Swift file with the Xcode target
docs/
  feature.md                How to build a feature, and the safety rules
  ui.md                     Theming, tokens, components, copy
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

The Dart package is still `mac_uninstaller` and the bundle id is still
`com.yunweneric.macuninstaller`. Both are deliberate: TCC grants — Full Disk
Access in particular — are keyed to the bundle id, so renaming it would cost
every existing install its permissions for no benefit. The product name lives in
`lib/core/design/brand.dart`.

## License

Private / unpublished.
