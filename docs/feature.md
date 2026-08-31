# Implementing a feature

This is how work is structured in Tidy. Read [ui.md](ui.md) for anything to do with
appearance; this file is about where code goes and what it must guarantee.

---

## 1. Decide which shape the feature is

Almost everything in this app is one of two things.

| Shape | When | What you write |
|---|---|---|
| **Scan module** | The feature finds things on disk and offers to remove them | A `ScanModule` implementation. No screen. |
| **Plain page** | The feature is a view, a control panel, or a setting | A widget wrapped in `ModuleScaffold`. |

If you are about to write a screen with a scan button, a results list and a
clean button — stop. That already exists once, in
`lib/core/scanning/presentation/scan_view.dart`, and it is written to be pointed
at any module. Writing a second one is the mistake this architecture exists to
prevent.

Two features are plain pages, and both for the same reason: **the scan
contract's verb is find → select → remove, and theirs is not.** Performance
turns a login item *off* and *runs* a maintenance task; Recycle Bin *puts
things back*, and what it lists was never found — the user put it there. Reach
for a plain page when the verb does not fit, not when the module feels big.

---

## 2. Directory layout

```
lib/features/<feature>/
├── data/
│   ├── models/          value types this feature owns
│   ├── services/        filesystem / process / channel access
│   └── <feature>_scan_module.dart
├── logic/               blocs, only if the feature needs state beyond ScanBloc
└── presentation/
    ├── <feature>_page.dart
    └── widgets/         widgets used only by this feature
```

A widget used by two features moves to `lib/core/widgets/`. A model used by two
features moves to `lib/core/`. Do not import across sibling features — if
`features/cleanup` needs something from `features/apps`, that thing belongs in
`core/`, with the exception of `features/apps`' own models and services, which
are the shared inventory of installed applications.

---

## 3. Building a scan module

### 3.1 Add the module id

`lib/core/scanning/domain/scan_module.dart` → `ModuleId`. The label and
description are user-visible and go straight onto the result tile, so write them
the way you would explain it to someone who does not know what a plist is.

```dart
developerJunk('Developer Junk', 'Build artefacts and package caches from your dev tools.'),
```

### 3.2 Implement `ScanModule`

```dart
abstract class ScanModule {
  ModuleId get id;
  IconData get icon;                    // from AppIcons — see ui.md
  bool get needsFullDiskAccess => false;
  bool get mayNeedAdmin => false;

  Stream<ScanProgress> scan(ScanRequest request);
}
```

`ScanRequest` gives you `root` (a folder or volume to narrow to, or null for the
module's defaults), `includeAdminItems`, and `hasFullDiskAccess`.

**Yield progress as you go.** A single `await` for the whole sweep leaves the
window on a spinner for tens of seconds, which reads as a hang. Emit after each
category:

```dart
@override
Stream<ScanProgress> scan(ScanRequest request) async* {
  yield const ScanProgress(roots: [], fraction: 0);

  final found = <ScanNode>[];
  for (var i = 0; i < categories.length; i++) {
    yield ScanProgress(
      roots: List.of(found),
      fraction: i / categories.length,
      currentPath: categories[i].label,   // drives the rolling status line
    );
    final node = await _scanCategory(categories[i]);
    if (node != null) found.add(node);
  }

  yield ScanProgress.done(found, skippedForPermission: /* see 3.4 */);
}
```

`lib/features/cleanup/data/cleanup_scan_module.dart` is the reference
implementation.

### 3.3 Build the `ScanNode` tree

```dart
ScanNode(
  id: item.path,        // stable across rescans — selection is keyed on it
  title: item.label,
  subtitle: collapseHome(parentDir, home),   // "~/Library/Caches"
  detail: 'One line saying what this is and why it is safe to remove.',
  paths: [item.path],   // everything removal touches
  sizeBytes: bytes,     // ALLOCATED, never logical — see 3.5
  safety: SafetyLevel.safe,
  requiresAdmin: false,
  sharesStorage: false,
  children: [...],      // a group node; its size is the sum of its children
)
```

Top-level children become the result **tiles**; everything below becomes the
**review tree**. You get both for free.

**`SafetyLevel` is the most consequential field you will set.** It decides what
is pre-ticked, and everything a user removes without reading was pre-ticked by
you.

| Level | Meaning | Pre-selected |
|---|---|---|
| `safe` | macOS or the owning app regenerates it on demand | Yes |
| `review` | Probably fine, but it is a judgement call | No |
| `risky` | User data, or irreversible | No, and confirmed separately |

If you are unsure, it is `review`. An inference about what a file *probably* is
— an orphan, an unused localisation, an old project — is never `safe`.

Set `requiresAdmin` for anything under `/Library` or otherwise root-owned. It is
shown and explained but not removable until the privileged helper lands
(Phase 5). Set `sharesStorage` for APFS clones and hard links: the bytes are
shared, so deleting frees nothing, and the UI says so.

### 3.4 Degrade honestly when access is denied

A denied read is not an empty folder. Catch `FileSystemException`, skip the root,
and set `skippedForPermission: true` on the final `ScanProgress`. The UI then
shows the Full Disk Access banner instead of a confident zero.

```dart
List<String> _childrenOf(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  try {
    return dir.listSync(followLinks: false).map((e) => e.path).toList();
  } on FileSystemException {
    _deniedRoots.add(root);   // report it; do not pretend it was empty
    return const [];
  }
}
```

### 3.5 Measure size correctly

Use `pathSizes` from `lib/core/utils/disk_utils.dart`. It batches into **one**
native call that walks with `fts(3)` on a background thread.

```dart
final sizes = await pathSizes(candidatePaths);   // Map<String, int>
```

- **Never** shell out to `du`. It was one process per path and it was the
  slowest thing in the app.
- **Never** call `pathSizeBytes` in a loop — that is one channel round trip each.
- Sizes are **allocated** (`st_blocks * 512`), not logical. On APFS the gap is
  not academic: `Docker.raw` reports 64 GB logically while occupying 8. Quoting
  the logical figure promises the user space that does not exist.

For per-item work the native side cannot batch (plist reads, icon fetches), use
`mapPooled` from the same file.

### 3.6 Register and route

```dart
// lib/core/di/service_locator.dart
locator.registerLazySingleton<DeveloperJunkModule>(
  () => DeveloperJunkModule(cache: locator<ScanCache>()),
);
```

Then the page is four lines:

```dart
class DeveloperJunkPage extends StatelessWidget {
  const DeveloperJunkPage({super.key});

  @override
  Widget build(BuildContext context) => ScanView(
    title: 'Developer Junk',
    subtitle: 'Build artefacts and caches your tools will rebuild.',
    idleHeadline: 'Reclaim your build output',
    actionLabel: 'Scan',
    onGrantAccess: locator<FullDiskAccessService>().openSettings,
  );
}
```

The page reads its `ScanBloc` from above, so provide it wherever the page is
mounted — see `ShellScaffold` for how Smart Care's bloc is hoisted so the
sidebar and the Dashboard read the same scan.

---

## 4. Adding a destination

1. Add a value to `AppDestination` in
   `lib/features/shell/domain/app_destination.dart` with `path`, `label`, `icon`,
   `group` and `blurb`.
2. Add the case to `_pageFor` in `lib/core/router/app_router.dart`.

That is all. Branches are generated from `AppDestination.values` in enum order,
and `branchIndex` keeps the router and sidebar from disagreeing.

**Branch order is load-bearing.** Inserting a value in the middle of the enum
renumbers every branch after it. Append unless you mean to reorder the sidebar.

Modules that are not built yet get a `ComingSoonPage` listing what they will do.
Never ship a scan button that finds nothing — a cleaner reporting "0 threats
found" from a scanner that does not exist is lying.

---

## 4a. Settings the native side reads

Most preferences are read by Dart and pushed to Swift over a channel. Three
sets cannot wait for that: the **clipboard recorder**, the **network readout**
and the **menu bar itself** all run before any Flutter engine has finished
starting, so they read `settings.json` themselves —
`ClipboardStore.readPrefsFromSettings()`, `NetworkStore.readPrefsFromSettings()`
and `MenuBarStore.readFromSettings()`.

That makes the key names a contract across the language boundary. `AppSettings`
owns them; `ClipboardPrefs.fromMap`, `NetworkPrefs.fromMap` and
`MenuBarPrefs.fromMap` on the Swift side read the same strings. **Renaming a key
in one place and not the other fails silently** — the native side simply falls
back to its default, which for the clipboard means recording more than the user
asked for, for the network readout means the wrong style in the menu bar for the
first second of every launch, and for the menu bar means the bar collapsing to
one icon and then sprouting three more once Dart catches up. All three sets
carry a comment saying so; keep it there.

One key is deliberately shared rather than duplicated:
`networkMenuBarEnabled` is both the network readout's switch and the menu bar's
"show the network item", and `MenuBarPrefs.fromMap` reads that exact string
rather than minting a `menuBarShowNetwork` beside it. Two keys for one switch is
two chances to drift.

The Dart side still pushes on change, through `ClipboardService.bindTo`,
`NetworkService.bindTo` and `MenuBarService.bindTo`. The file read is for
launch; the channel is for everything after it.

---

## 4b. Logging

Everything goes through `AppLog` in `lib/core/logging/`. There is no `print` and
no `debugPrint` left in `lib/`, and adding one back is a review comment.

```dart
import 'package:tidy/core/logging/logging.dart';

AppLog.apps.debug('scan started', fields: {'root': root});
AppLog.apps.failed('list an applications folder', e, fields: {'root': root});
```

**Pick the channel your feature already owns** — the list is the constants on
`AppLog`. A feature with no channel adds one there rather than passing a string;
the channel is the column that makes the interleaved output of a dozen
concurrent services readable, and one-off names defeat that.

**Put the values in `fields`, not in the sentence.** `failed('list an
applications folder', e, fields: {'root': root})` and not
`failed('list $root', e)`. The message is what makes two occurrences the same
event; the fields are what makes one of them findable.

**Level means "how broken", not "how interesting".**

| Level | Means |
|---|---|
| `trace` | per-item work inside a loop; off by default |
| `debug` | one operation narrating itself |
| `info` | something the user could feel — a scan's totals, the app starting |
| `warn` / `failed` | it failed and the caller carried on with a fallback |
| `error` | it failed and the feature did not recover |
| `fatal` | the app cannot continue |

Nearly every log in this app is `failed` — the catch block that returns an empty
list so a page renders without its numbers rather than not at all. Name the
operation as a bare verb phrase (`'read the trash ledger'`); the method prints
it as `could not read the trash ledger`.

**A swallowed exception must be logged.** A `catch` that returns a fallback and
says nothing is indistinguishable from success, and in this app the fallback is
usually an empty result — which reads on screen as "there is nothing here"
rather than "we could not look".

Debug builds log at `debug`, release at `warning`; `--dart-define=TIDY_LOG_LEVEL=trace`
overrides both, including in a release build, which is how you turn the noise up
on a shipped app without changing the timings that caused the bug.

---

## 5. The rules that are not negotiable

This app deletes files. These are the parts where a bug is not a bug report, it
is someone's data.

**Match exactly, never by substring.** `"Mail"` matches `~/Library/Mail`.
`"Music"` matches `~/Music`. `LeftoverScanner._matches` is the pattern to copy:
exact bundle id, bundle-id prefix (`com.acme.App.`), team-prefixed suffix, and
exact display-name match guarded by an ambiguous-names list.

**Constrain to your roots.** Every candidate must be a direct child of a root you
declared. `LeftoverScanner._isSafeToRemove` rejects anything that escaped, and
anything under `/System`.

**Never weaken `SystemChannel.isRemovable`.** It is the last line of defence
before `FileManager` is called, it resolves symlinks before checking, and it
refuses mount points. Its `protectedPaths` set only ever *grows*. If a new
scanner is being refused, the scanner is wrong.

**Paths that are permanently off limits**, regardless of size:
- `.photoslibrary`, `.musiclibrary`, `.tvlibrary` internals — especially
  `resources/derivatives`. Every cleaner that has touched them has corrupted
  libraries. Treat packages as opaque (`URLResourceKey.isPackage`).
- pnpm's content-addressed store — `node_modules` hard-links into it, so
  deleting it breaks every installed project. Use `pnpm store prune`.
- `Docker.raw`. Offer `docker system prune` instead.
- `CoreSimulator/Devices` by hand. `device_set.plist` is the index; use
  `xcrun simctl delete unavailable`.
- `.lproj` stripping and `lipo` thinning. Both invalidate code signatures, which
  on macOS 13+ can stop a notarized app launching. Report the size, never offer
  the action.
- The Trash **folders** — `~/.Trash`, and any volume's `.Trashes/<uid>`.
  Emptying the bin removes what is *inside* them; removing the folder itself
  takes the thing macOS puts deleted files into, and Finder does not reliably
  recreate it. `SystemChannel.isTrashRoot` refuses all three shapes.

**Prefer the tool's own cleanup command** over `rm -rf` — `brew cleanup -s`,
`npm cache clean`, `go clean -modcache`, `pod cache clean --all`. It keeps
lockfiles consistent, and "we ran `brew cleanup`" is a far better story than
"we deleted 4 GB of unknown files".

**A missing sample is not a zero.** Anything that records over time — the
network history is the first, and will not be the last — only records while
Tidy is running. A period with no row is a period the app was quit for, and it
has to be drawn as a gap and said out loud. Rendering it as a zero tells the
user they used nothing overnight, which is the same class of lie as a scanner
reporting "0 threats found" from a scanner that does not exist.

**Trashing frees nothing** until the Trash is emptied. Copy says "moved to
Trash", never "freed". Recycle Bin's permanent delete is the one exception —
that one genuinely frees the bytes, and is allowed to say so.

**Every removal is written down.** `lib/core/store/tidy_store.dart` records one
row per operation and one per file removed — path, size, category, and whether it
was trashed or deleted outright. It is what the Dashboard's charts are drawn from
and, more importantly, it is the only thing that makes a wrong deletion
auditable after the fact. Unlike `TrashLedger` this cannot live at a single choke
point, because the sizes and categories only exist at the caller: if you add a
path that removes things, record it where you build the outcome. `ScanBloc`,
`AppsBloc`, `RecycleBinBloc` and `MaintenanceService` are the four that do.

`bytes_trashed` and `bytes_deleted` are separate columns and must stay that way.
Trashing frees nothing until the Trash is emptied, so summing them into one
"space reclaimed" figure promises the user space they do not have.

**Every route to the Trash goes through `SystemBridge.trashItems`**, which
records where each item came from in `TrashLedger`. macOS keeps Finder's
put-back index in a binary `.DS_Store` no other app can read, and
`FileManager.trashItem` writes no record at all, so that ledger is the only
reason Recycle Bin can offer "Put Back". A scanner that trashes files by some
other route silently costs the user that.

---

## 6. Before you call it done

- [ ] `dart analyze lib` is clean.
- [ ] No `print` or `debugPrint` — every log goes through `AppLog`, and every
      swallowed exception logs something.
- [ ] Ran with Full Disk Access **granted and revoked**
      (`tccutil reset SystemPolicyAllFiles com.yunweneric.tidy`).
      Denied must degrade to a partial result with the banner, never a crash and
      never a silent zero.
- [ ] Sizes checked against `du -sh` **and** against a sparse file.
- [ ] Dry-run diffed: log the removal set before enabling real removal.
- [ ] First painted result under 2s; full scan under 30s.
- [ ] `isRemovable` still refuses every protected path, including a symlink
      pointing out of an allowed root and a mount point.
- [ ] Tested from the built `.app`, not `flutter run` — TCC grants are keyed to
      the bundle.

Tests are not written by default in this repo. The exception worth raising: the
path-safety predicates (`isRemovable`, `_isSafeToRemove`, each scanner's root
constraints) are the only code here that can destroy data. If you add a scanner,
say so and ask.
