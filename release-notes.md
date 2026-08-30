## 🧹 Tidy v1.0.14

| Download | For |
| --- | --- |
| `Tidy-1.0.14.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.14-macos.zip` | What the in-app updater downloads |

> **Unsigned build.** Tidy is not signed with a Developer ID and not
> notarized, so the first launch is blocked: open **System Settings →
> Privacy & Security** and choose **Open Anyway** (right-click → Open no
> longer bypasses Gatekeeper on macOS 15+). Updates are verified against
> the SHA-256 digest published below rather than a code signature.

Tidy runs outside the App Sandbox so it can inspect `/Applications`
and `~/Library`. Grant it **Full Disk Access** in System Settings and
relaunch — macOS caches that decision per process, so the grant only
takes effect after a restart of the app.

Verify your download against `SHA256SUMS.txt`:
`shasum -a 256 -c SHA256SUMS.txt --ignore-missing`

---

### One sweep

**Cleanup is gone from the sidebar, and Smart Care now runs everything.** The
two pages were always overlapping — Smart Care ran Cleanup's checks and then
some — but each owned its own scan, so `~/Library` was swept twice to produce
two different answers to "how much can I get back", and the smaller one had a
page of its own. There is one sweep now: caches, logs and saved window state,
the build output and package caches your developer tools leave behind, and the
applications you have not opened in months, all in a single pass and a single
list.

- **The rail quotes what is actually ticked.** The sweep now finds
  applications as well as junk, and an application is never pre-selected — so
  the sidebar's reclaim figure and the Dashboard's counter changed from "every
  byte we found" to "what one click on Clean would remove". A rail promising
  60 GB when the button frees 8 was overstating it.
- **The page says what it walks past.** pnpm's store, Docker's disk image, your
  simulator devices and installed SDKs are deliberately left alone — deleting
  any of them breaks projects that are still using it — and the page now names
  them, with the command each tool provides for doing it safely.

### Also in this release

- **Release notes are set in the app's own type.** The Updates card was showing
  the GitHub release body as raw text: readers were handed `## 🧹 Tidy v1.0.13`,
  a row of `| --- |`, and every asterisk that was meant to make a word bold.
  The page you are reading now renders properly inside the app.

### What changed since v1.0.13

- Set release notes in the app's own type instead of printing their source ([`ebdd35d`](https://github.com/yunweneric/tidy/commit/ebdd35da259547ce7d528e6b2d2e443375de75d9))
- Refactor Cleanup module into Smart Care, consolidating functionality for a single sweep ([`85c0451`](https://github.com/yunweneric/tidy/commit/85c0451826f44d9a8490aa0b8d32622913364dd7))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.13...v1.0.14
