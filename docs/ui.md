# Theming and styling

For where code goes and what a feature must guarantee, see
[feature.md](feature.md). This file is about appearance.

One rule underneath everything here: **no widget hard-codes a colour, size,
radius, duration or icon.** Every one of those comes from a token. That is not
tidiness — it is the only reason light mode works, and the only reason Reduce
Motion is a switch rather than a scavenger hunt across thirty files.

---

## 1. Where the design system lives

```
lib/core/design/
├── design.dart              barrel — import this
├── app_theme.dart           TidyTheme.light() / .dark()
├── app_icons.dart           every glyph in the app
├── brand.dart               name, mark, tagline
├── context_ext.dart         context.colors / .text / .motion
└── tokens/
    ├── app_color_tokens.dart    ThemeExtension, light + dark
    ├── app_typography.dart      ThemeExtension, resolved against colours
    ├── app_spacing.dart         static consts
    ├── app_radii.dart           static consts
    └── app_motion.dart          ThemeExtension, carries reduceMotion
```

```dart
import 'package:tidy/core/design/design.dart';
```

---

## 2. How it resolves

Colours, typography and motion are `ThemeExtension`s installed on `ThemeData`,
so they change with the theme. Spacing and radii are plain static constants —
they do not vary by brightness, so they do not need to be looked up.

```dart
final colors = context.colors;   // AppColorTokens
final type   = context.text;     // AppTypography
final motion = context.motion;   // AppMotion

Container(
  padding: const EdgeInsets.all(AppSpacing.lg),     // static, const-friendly
  decoration: BoxDecoration(
    color: colors.surface,
    borderRadius: AppRadii.lgAll,
    border: Border.all(color: colors.border),
  ),
  child: Text('Xcode', style: type.titleS),
)
```

There is **no `context.space`** — use `AppSpacing.lg` directly. It is `const`,
which matters inside `const` constructors.

> **Why this is strict.** Before the token layer, ~30 widgets imported a static
> dark-only palette. In light mode they rendered near-white text on white, and
> version badges came out as dark pills on a white table. Any widget reaching
> past `context.colors` reintroduces exactly that.

---

## 3. Colour tokens

Named by role, never by hue — `colors.risky`, not `colors.red`. A token whose
name describes its appearance stops being reusable the moment the palette moves.

### Backdrop

**The module's colour is the window.** It is not a tint over a neutral canvas —
Cleanup *is* green, Protection *is* magenta, edge to edge, sidebar included.
`AmbientBackground` paints it: a base-to-lift ramp, a pool of the module's own
light high and slightly left, a weaker one bottom-right, two oversized ring
outlines and a dot grid.

| Token | Use |
|---|---|
| `canvas` | Flat fallback. Only where a gradient cannot go (`scaffoldBackgroundColor`) |
| `canvasGradient` | The backdrop where no module owns the view |
| `modulePalettes` | Every module's `base` + `lift`. Read via `colors.modulePalette(tone)` |
| `glowStrength` | How hard the light pools. Light mode uses a fraction of dark's |
| `pattern` | Ink for the ring outlines and the dot grid |

`ModulePalette.ramp` is the gradient a primary action wears inside that module.
`ModuleTint.of(context)` hands it to any widget below `AmbientBackground`, which
is how `GradientButton` and `GaugeRing` come out the right colour without a
single page passing one down by hand.

The light and the pattern are near-invisible on purpose. The light is depth,
the shapes are scale, the dots are texture — if a pattern is legible enough to
count, it is too strong.

### Surfaces

**Surfaces are neutral veils, not colours.** A card is white at 8% in dark and
white at 72% in light. It has no hue of its own, so it takes whatever module is
behind it and blends into it — which is the whole reason a green module and a
magenta one can share one set of components. Nothing in the window is opaque
except the things that float over it.

| Token | Use |
|---|---|
| `sidebar` / `sidebarGradient` | Darkens (dark) or lightens (light) the rail against the module colour |
| `surface` | Default card / tile / table background |
| `surfaceGradient` | The card veil. What `TidyCard` and the table frames fill with |
| `surfaceOpaque` | The neutral solid surface: popup menus, tooltips, the menu-bar popover |
| `floatingSurface(palette)` | The solid surface for a dialog or toast — `surfaceOpaque` remade in the module's own colour |
| `surfaceRaised` | Sits on top of `surface` — inputs, nested rows, segmented track |
| `surfaceHover` | Hover and pressed wash, and the selected sidebar row |
| `overlay` | Scrim behind dialogs |

If a surface has to hide what is behind it, it needs `surfaceOpaque` — a sheer
dialog over a table of file paths is unreadable. Everything else stays sheer.

**Never give a surface a hue.** The moment a card carries its own colour it
stops blending and starts fighting whichever module it lands on. Two
exceptions, both narrow:

- `TidyCard(tint:)` layers a semantic colour *onto* the veil rather than
  replacing it, and only where the colour is the information.
- `floatingSurface(palette)` — dialogs and toasts. Everything sheer blends by
  being sheer; these cannot, because they have to hide what is behind them. So
  they blend by being *made of* the module instead: its `base` warmed toward
  its `lift` and veiled in dark, its `lift` under a heavy white veil in light.
  A solid neutral panel dropped on an amber window reads as a screenshot from
  a different app.

Dialogs and toasts sit in the **root overlay**, above `AmbientBackground`, so
they cannot look the palette up for themselves — `showTidyDialog` and
`TidyToaster.show` capture it with `ModuleTint.read(context)` at the call site
and re-provide it. That is also what makes a dialog's primary `GradientButton`
wear the module's ramp instead of falling back to the brand one.

### Traffic
| Token | Use |
|---|---|
| `downstream` | Bytes coming in — the download series on every network chart |
| `upstream` | Bytes going out |

A pair of their own rather than borrowed status colours. `safe` / `review` /
`risky` mean the same thing on every module in the app, and a green "download"
against an amber "upload" would quietly teach that one direction is fine and the
other needs looking at. They cannot be the module ramp either: a two-series chart
needs two colours, and a ramp is one.

### Lines
| Token | Use |
|---|---|
| `border` | Default 1px separator and card outline |
| `borderStrong` | A deliberately visible edge — focused input, checkbox outline |

### Text
`textPrimary` · `textSecondary` · `textMuted` · `textOnAccent`

Text sits on module colour as often as on a card, so `textSecondary` and
`textMuted` are `textPrimary` at reduced alpha rather than their own grey. A
cool grey turns muddy the moment the backdrop behind it is green or amber.

`textOnAccent` is for text sitting on a status fill. Never use `Colors.white`
for that — it is wrong in light mode the moment the fill moves.

### Brand
| Token | Use |
|---|---|
| `accent` | The signature colour, for brand moments and links |
| `accentMuted` | Low-opacity accent wash. Brand moments only |
| `accentGradient` | The brand ramp — mark, onboarding panel, and CTAs outside any module |

The rule is not "no gradients" — a gradient means one of two things and nothing
else:

- **Backdrop.** The module's ramp, behind everything.
- **Press this / watch this.** `ModulePalette.ramp` on `GradientButton` and
  `GaugeRing`, falling back to `accentGradient` outside a module.

Everything else is a neutral veil. Ordinary buttons are `surfaceHover` with
`textPrimary` — a translucent white pill — so the one action wearing a colour
is unmistakably the one that matters. One `GradientButton` per screen.

**Accent is not a substitute for the module colour.** A selected sidebar row
uses `surfaceHover`, not `accentMuted`: a blue wash on a green page is a
mistake with extra steps.

### Module tones

A view that owns a colour of light tells you where you are before you have read
the page title:

| Module | Tone | | Module | Tone |
|---|---|---|---|---|
| Smart Care | gold | | Space Lens | purple |
| Cleanup | green | | Network | azure |
| Protection | magenta | | Dashboard | brand violet |
| Performance | amber | | Clipboard | brand violet |
| Applications | indigo-blue | | My Clutter | teal |
| AI Usage | orchid | | | |

Smart Care was violet until the Dashboard arrived above it in the rail wearing
the same brand violet. Two adjacent rows opening into an identical window is
exactly what the tone exists to prevent, so Smart Care took the widest unused
arc on the wheel instead — a citrine gold at ~58°, 37° clear of Performance's
burnt orange and 44° clear of Cleanup's green.

`AppDestination.tone` names the tone; `colors.modulePalette(tone)` resolves it.
`AmbientBackground` paints the window with it and cross-fades the whole palette
over `motion.slow` when you change module — base and lift move together, so the
window never passes through a hue neither module owns.

Supporting views (All Tools, Activity, Assistant, Settings, Recycle Bin) keep
the brand tone. A hue per destination means nothing; a hue per *place you spend
time in* means something, and that is the line — the six working modules, plus
the ones you go to in order to watch something (Space Lens, Network, AI Usage).
A proposed tone has to answer which of those it is before it gets a hue.

AI Usage is the ninth, and it took what was left. By the time it was asked for,
the wheel was occupied at 24° (Performance), 57° (Smart Care), 101° (Cleanup),
173° (My Clutter), 197° (Network), 248° (brand and Applications), 267° (Space
Lens) and 317° (Protection), with the status hues at 39° / 143° / 197° / 355°.
Two arcs were left. **~137°** had the widest module clearance of anything
available — 36°, against Smart Care's 37° — and sat 6° from the `safe` green;
it was rejected not for the 6° but for what green *means* here, since a module
with nothing to do with deletion wearing "safe to delete" edge to edge is a
semantic collision rather than a hue one. **~290°** was taken instead: 23° from
Space Lens and 27° from Protection, tighter than any existing pair, so its
saturation is pulled well below Space Lens's (76% against 87% at the accent) to
hold the two apart by weight as well as by hue.

Blues and purples are close together, and deliberately not adjacent in the
sidebar: Applications is a working module while Network and AI Usage are under
MORE, and AI Usage sits four rows below Space Lens, so no two neighbouring rows
open into the same-looking window.

Status colours stay `safe`/`review`/`risky` on every module — those mean what
they mean regardless of what colour the window is. Amber has to keep reading as
"look at this" and not as "you are in Performance", which is exactly why the
module colour lives in the backdrop and the CTA, and nowhere else.

### Status
| Token | Meaning |
|---|---|
| `safe` | Regenerated automatically; safe to remove |
| `review` | Worth a look before removing |
| `risky` | Destructive, or user data |
| `info` | Neutral advisory |

These map one-to-one onto `SafetyLevel`, which is what makes
`StatusChip.safety(level, context)` possible.

---

## 4. Type scale

| Token | Size / weight | Use |
|---|---|---|
| `displayXl` | 56 / 700 | The reclaimable-bytes number on a scan hero. Nothing else |
| `displayL` | 30 / 700 | Tile headline numbers, stat cards |
| `titleL` | 24 / 700 | Page title |
| `titleM` | 17 / 600 | Card and section titles, dialog titles |
| `titleS` | 14 / 600 | Row title, emphasised body |
| `bodyL` | 15 / 400 | Body on a surface, menu items |
| `bodyM` | 13 / 400 | Default body — secondary colour |
| `bodyS` | 12 / 400 | Dense explanatory text |
| `label` | 13 / 500 | Buttons, nav items, chips |
| `caption` | 11 / 400 | Metadata under a row, muted colour |
| `overline` | 11 / 600, +0.7 tracking | Uppercase section labels, table headers |
| `mono` | 12 monospace | Filesystem paths |

Styles **carry their colour**. That is deliberate: it removes the most common
way a dark theme springs a leak — the right size paired with the wrong colour.
Override with `.copyWith(color: colors.x)` when a row genuinely needs emphasis,
not as a habit.

`displayXl` and `displayL` use tabular figures, so a counting animation and a
column of sizes do not jitter as digits change.

---

## 5. Spacing and radii

4pt scale. `xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 28 · xxxl 40 ·
huge 64`, plus composites `AppSpacing.page`, `.card`, `.row`.

Radii have jobs rather than being a free choice:

| Token | Value | Use |
|---|---|---|
| `xs` | 4 | Checkboxes, progress bars |
| `sm` | 6 | Badges, chips, page buttons, segmented pills |
| `md` | 10 | Buttons, inputs, nav items, icon tiles |
| `lg` | 14 | Cards, tiles, panels |
| `xl` | 20 | Dialogs, sheets, hero surfaces |
| `pill` | 999 | Pills, avatars, dots |

Each has an `…All` `BorderRadius` constant: `AppRadii.lgAll`.

---

## 6. Motion

| Token | Duration | Use |
|---|---|---|
| `fast` | 120ms | Hover, press |
| `normal` | 180ms | Expand, select, swap |
| `slow` | 320ms | Page and panel transitions |
| `hero` | 900ms | Byte counter tween, ring sweep |
| `ringSpin` | 2400ms | One rotation of the indeterminate ring |

Curves: `standard` (`easeOutCubic` — decelerates hard, reads as responsive),
`enter` (`easeOutBack`), `smooth` (`easeInOutCubic`).

**Every duration token collapses to zero when Reduce Motion is on**, so
`AnimatedContainer(duration: context.motion.fast)` needs no guard. Animation
*controllers* do — check `context.motion.reduced` and jump to the end value:

```dart
if (context.motion.reduced) {
  _controller.value = 1;
} else {
  _controller.forward(from: 0);
}
```

Also stop tickers that are no longer needed. `GaugeRing` only spins while the
scan is genuinely indeterminate; a controller left running behind a finished
scan is a silent battery cost.

### Route transitions
Fade, never slide — macOS windows do not slide their content sideways.
`FadePage` for top-level routes, `FadeThrough` for switching shell branches.
Do not reach for `AnimatedSwitcher` around the navigation shell: it holds both
children on screen at once, and the branch navigators carry global keys, so two
live copies is a duplicate-`GlobalKey` crash.

---

## 7. Icons

Every glyph goes through `AppIcons`, a named registry over `hugeicons`.

```dart
Icon(AppIcons.delete, size: 17, color: colors.risky)
```

- **Never** `Icons.*` (Material) and **never** `HugeIcons.*` directly. The
  registry means the whole set is swappable in one file, and names describe
  meaning (`AppIcons.risky`) rather than appearance (`AppIcons.triangle`).
- Sizes: 15 in dense rows, 17–19 in buttons and cards, 20–22 in headers,
  30–44 in empty states and heroes.
- Adding a glyph: add a named constant to `app_icons.dart`. Do not import the
  package at a call site.

### The app icon

The product mark — a Mac screen with a four-point spark in it, on the brand
violet ramp — is *not* an `AppIcons` glyph. It is one drawing that has to appear
in five places, so it exists twice, on purpose:

| Where | What draws it |
| --- | --- |
| Sidebar, splash, anywhere in Dart | `BrandMark` — a `CustomPaint`, no asset |
| Dock, Finder, taskbar, favicon | `assets/icon/*.png` via `flutter_launcher_icons` |
| macOS menu bar | `macos/.../MenuBarIcon.imageset`, a template image |
| Android / iOS / web launch screen | `flutter_native_splash` |
| Linux window | `linux/runner/resources/app_icon.png`, set in `my_application.cc` |

Everything under `assets/icon/` is generated. The one source of truth is
`scripts/generate_icons.py`, which writes the SVGs *and* rasterises them:

```sh
python3 scripts/generate_icons.py          # redraw the sources
dart run flutter_launcher_icons            # fan out to the platforms
dart run flutter_native_splash:create      # and the launch screens
```

`BrandMark` repeats the geometry in Dart rather than loading a PNG because it is
asked for at 30pt in the rail and 108pt on the splash: an asset would need a
variant per size and would still be soft on a scaled display. If the mark
changes, both the script and `brand_mark.dart` have to change — that is the
cost of it being crisp at every size, and it is four paths.

The tile ramp is a fixed constant, not a colour token. An icon that follows the
OS appearance is not an identity.

---

## 8. Components

Reach for these before building anything.

| Component | Use |
|---|---|
| `ModuleScaffold` | The page frame every module wears — title, subtitle, actions, banner |
| `TidyCard` | The standard surface. Handles hover, selection, accent |
| `StatusChip` | Small tinted label. `StatusChip.safety(level, context)` for tiers |
| `EmptyState` | Nothing-here: icon, headline, one line, optional action |
| `SizeBar` | Thin proportional bar — "this row is 40% of the category" |
| `GaugeRing` | The radial scan gauge, determinate or sweeping |
| `AnimatedBytes` | A byte count that counts up rather than snapping |
| `SegmentedTabs` | macOS-style segmented control, with optional counts |
| `DataTableHeader` | Table header with tri-state select-all, fixed widths, sort carets |
| `PaginationBar` | Windowed pagination (1 … 7 8 9 … 19) |
| `PermissionBanner` | Full Disk Access prompt, full or compact |
| `FadeThrough` | Fades content back in when a trigger changes |
| `BucketBarChart` | A time series as stacked bars. Unrecorded periods draw as gaps, never as zeroes |
| `BucketLineChart` | A level over time as a filled line, broken across gaps rather than interpolated |
| `StackedBar` | A composition as one horizontal bar — what makes up a whole |
| `AmbientBackground` | The window backdrop — wash, glows, shapes, dot grid. Wraps the whole window |
| `GradientButton` | The primary call to action, wearing `accentGradient` |
| `TidyToast` | Transient result in the corner of the window — `context.toastSuccess('…')` |
| `TidyDialog` | The modal frame: medallion, title, scrolling body, footer |
| `TidyAlert` | A question (`.confirm`) or a report (`.notify`), built on `TidyDialog` |


### Telling the user what happened

Lives in `lib/core/feedback/` — `import 'package:tidy/core/feedback/feedback.dart';`

**If the user has to do something about it, it is an alert. If they only have
to know, it is a toast.** A finished uninstall is news; a permanent delete is a
question. Nothing in the app builds either by hand, and `SnackBar`,
`AlertDialog` and `showDialog` are not used directly any more.

Both pick a `FeedbackTone` — `success` · `warning` · `danger` · `info` ·
`neutral` — and the tokens resolve the colour, the glyph, and how long a toast
stays up. A call site never pairs a message with a colour, which is what stops
"amber" drifting from meaning *look at this* to meaning *Performance*.

```dart
context.toastSuccess('1.2 GB moved to Trash', title: '3 items removed');

final ok = await TidyAlert.confirm(
  context,
  title: 'Delete permanently?',
  message: 'Nothing here can be recovered afterwards.',
  confirmLabel: 'Delete permanently',
  destructive: true,
);
```

**Toasts.** Bottom-right, stacked newest-nearest-the-corner, three at a time —
beyond that the oldest retires early, because a column of six is a log and
nobody reads a log that is dismissing itself. They live in the **root overlay**
rather than the page, so a result that arrives while the user is navigating
away is still seen, and a rebuilding module does not take its own confirmation
down with it. The tone shows as a 3px left rail and a tinted icon tile and
nowhere else: the one button on a toast is a neutral `surfaceRaised` pill, so
the colour is saying one thing rather than two. Hovering freezes the lifetime
hairline — a toast that vanishes mid-sentence is worse than no toast.

At most one action, and it opens something rather than deciding something. A
toast with a real choice on it is an alert that has not admitted it yet.

**Nothing destructive happens without both.** Every action that removes,
trashes or quits something asks first with a `TidyAlert.confirm` and reports
afterwards with a toast. The confirm says what actually goes and what "gone"
means here — trashed things come back, deleted things do not, and a quit
background process is usually restarted by macOS a second later. The one
exception is the Cleanup/Smart Care sweep, whose report is a whole screen
(`RemovalSummary`) rather than a toast, because it has a byte counter and a
failure list in it.

**Alerts.** `showTidyDialog` rather than `showDialog`, so the scrim is
`colors.overlay` and the transition honours Reduce Motion. The frame is
`surfaceOpaque` at `AppRadii.xl`; the body scrolls inside `maxContentHeight`
so the footer never leaves the screen at 1100×720. `AlertDetail` renders the
per-item explanation block — a path in `mono`, the reason under it in the
tone's colour.

Footer buttons are `TidyDialogAction`, which is where the one-gradient-button
rule is kept for modals: `quiet` for the way out, exactly one `primary`
(module ramp), or `destructive` (solid `risky`) when the action removes
something. A gradient makes a delete button look inviting, so a delete button
never gets one.

### Cards
Sheer two-stop fill (`surfaceGradient`), 1px border, no Material elevation.
Shadows read as heavy next to macOS's own chrome, and a consistent border is
what keeps a dense screen legible. `elevation: 0` everywhere.

The one shadow in the app is the accent glow under a hovered `GradientButton`,
which stands in for the elevation nothing else uses.

### Tables
Header and rows share **one** geometry spec — see `AppTableLayout` in
`app_table_row.dart`. Header and rows each declaring their own flex values is
how a table ends up with labels that do not sit above their data.

Use fixed widths for short, predictable columns (version, size); flex for prose
(name, developer). Right-align numerics. Destructive row actions appear on
**hover only** — a red glyph on every row turns a list of your own apps into a
wall of warnings.

---

## 9. Writing the words

Copy is part of the design system here, and gets the same scrutiny as spacing.

- **Plain language.** These modules are for people who do not know what a plist
  is. "Files left behind by apps you no longer have", not "orphaned bundle
  identifiers".
- **Never overclaim.** Trashing frees nothing until the Trash is emptied, so the
  summary says "moved to Trash" and names what is still to be reclaimed.
  Cloned files free nothing, and say so.
- **An empty result is not a failure.** "Nothing to clean up — that is a good
  sign, not a failed scan."
- **Explain permissions before asking.** A cleaner that demands Full Disk Access
  with no explanation is indistinguishable from malware.
- **Say what is not built.** A scan button that finds nothing is worse than an
  honest empty page.
- Curly quotes (`“ ”`, `’`) in user-facing strings.

---

## 10. Adding a token

1. Add the field to the relevant token class.
2. Give it a value in **both** `.dark()` and `.light()`.
3. Extend `copyWith` and `lerp` — `lerp` is what makes a theme change animate
   rather than snap.
4. Document what it is *for*, not what it looks like.

If you find yourself wanting a one-off colour, that is usually a sign the
component wants an `accent` parameter instead — `TidyCard` and `StatusChip` both
take one, so a card can glow in its own semantic colour without a new token.

---

## 11. Quick check

- [ ] No `Color(0x…)`, `Colors.*`, or raw numeric padding outside the token files
- [ ] No `Icons.*` or `HugeIcons.*` outside `app_icons.dart`
- [ ] No `TextStyle(fontSize: …)` inline — use the scale
- [ ] Animation controllers honour `context.motion.reduced`
- [ ] Viewed in **both** light and dark
- [ ] Anything that floats over the window uses `surfaceOpaque`, not `surface`
- [ ] At most one `GradientButton` on the screen — a dialog counts as its own
- [ ] No `SnackBar`, `AlertDialog` or bare `showDialog` — toast or `TidyAlert`
- [ ] No surface carries a hue of its own — checked on a green module *and* a magenta one
- [ ] Nothing breaks at the 1100×720 minimum window size
