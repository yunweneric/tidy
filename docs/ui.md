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
import 'package:mac_uninstaller/core/design/design.dart';
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

### Surfaces

Every in-window surface is **translucent**. The backdrop is one continuous
thing that runs under the sidebar, the cards and the tables alike, and it is
what makes the window read as a single surface instead of a set of panels
pasted onto a picture. Exactly one token is solid, and it is for the things
that float *over* the window.

| Token | Use |
|---|---|
| `canvas` | Flat fallback behind everything. Only where a gradient cannot go |
| `canvasGradient` | The backdrop wash, painted by `AmbientBackground` |
| `sidebar` / `sidebarGradient` | The left rail's veil — sheer, so the backdrop carries through |
| `surface` | Default card / tile / table background. **Sheer** |
| `surfaceGradient` | The card sheen. What `TidyCard` and the table frames fill with |
| `surfaceOpaque` | The one solid surface: dialogs, popup menus, tooltips, snackbars, the menu-bar popover |
| `surfaceRaised` | Sits on top of `surface` — inputs, nested rows, segmented track |
| `surfaceHover` | Hover and pressed wash |
| `overlay` | Scrim behind dialogs |

If a surface hides what is behind it, it needs `surfaceOpaque` — a sheer dialog
sitting on a table of file paths is unreadable. Everything else stays sheer.

### Ambient light
| Token | Use |
|---|---|
| `glowPrimary` | The violet pool in the top-left of the window |
| `glowSecondary` | The teal counterweight, bottom-right |
| `pattern` | Ink for the backdrop's ring outlines and dot grid |

All three carry their own alpha and are composited over `canvasGradient`. None
of them is ever a fill. They are near-invisible on purpose: if a pattern is
legible enough to count, it is too strong.

### Lines
| Token | Use |
|---|---|
| `border` | Default 1px separator and card outline |
| `borderStrong` | A deliberately visible edge — focused input, checkbox outline |

### Text
`textPrimary` · `textSecondary` · `textMuted` · `textOnAccent`

`textOnAccent` is for text sitting on `accent` or a status fill. Never use
`Colors.white` for that — it is wrong in light mode the moment the accent moves.

### Brand
| Token | Use |
|---|---|
| `accent` | The single signature colour |
| `accentMuted` | Low-opacity wash — selected nav item, icon tile |
| `accentGradient` | `List<Color>`. Brand mark, scan ring, and every primary CTA |

The rule is not "no gradients" — it is that a gradient means one of two things
and nothing else:

- **Backdrop.** `canvasGradient` plus the glows and shapes, behind everything.
- **Press this / watch this.** `accentGradient`, on the brand mark, the scan
  ring and `GradientButton`.

Card fills use `surfaceGradient`, which is two neighbouring tints of the same
colour — a surface catching light, not a decoration. `TidyCard(tint:)` washes a
tile in a semantic colour when **the colour is the information** (amber for
apps gone unopened, green for a clean result). Never on a row in a list: a
table where every row is tinted is a table with no signal left.

One `GradientButton` per screen. A page where everything glows has told the
user nothing about what to press.

### Module tones

Each of the six modules owns a colour of light, so the window tells you where
you are before you have read the page title:

| Module | Tone |
|---|---|
| Smart Care | brand violet |
| Cleanup | blue |
| Protection | pink |
| Performance | amber |
| Applications | cyan-blue |
| My Clutter | teal |
| Space Lens | deep violet |

`AppDestination.tone` names the tone; `colors.moduleTint(tone)` resolves it.
`AmbientBackground` swaps it in for `glowPrimary` and washes a few percent into
the canvas, cross-fading over `motion.slow` when you change module.

Supporting views (All Tools, Activity, Assistant, Settings) keep the brand
tone. A hue per module means something while there are six of them; it stops
meaning anything at eleven.

**The tone is light, not paint.** It never restyles the content — buttons stay
brand-accented, status colours stay `safe`/`review`/`risky`, and a tinted card
still uses its own semantic colour. Anything else and "amber" stops reading as
"you are in Performance" and starts reading as "something needs attention".

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
| `AmbientBackground` | The window backdrop — wash, glows, shapes, dot grid. Wraps the whole window |
| `GradientButton` | The primary call to action, wearing `accentGradient` |

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
- [ ] At most one `GradientButton` on the screen
- [ ] Nothing breaks at the 1100×720 minimum window size
