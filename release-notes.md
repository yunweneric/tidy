## 🧹 Tidy v1.0.18

| Download | For |
| --- | --- |
| `Tidy-1.0.18.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.18-macos.zip` | What the in-app updater downloads |

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

### The gauge popover is about your Mac again

The overview panel behind the gauge icon had grown into a summary of the whole
app: the network rate, a teaser of your clipboard history and the reclaimable
totals, all sitting under the vitals — and each of them repeating a surface that
already has its own item on the menu bar and its own tab inside the same
popover.

It now answers one question, which is the one its icon promises: **is this Mac
struggling, and what is doing it.**

- The three gauges, and the one thing worth acting on.
- **Memory pressure, swap and load average** — new on screen, and not new to the
  app. They have been sampled every two seconds since the sampler landed and
  shown nowhere, and they are what make the gauges mean anything: 85% memory is
  ordinary on a Mac, while 85% with pressure high and swap in use is the machine
  working for it. Each colours only when it crosses something, so an uncoloured
  row reads as "nothing to see" without having to say so.
- What is using the machine right now.

Clipboard, network and what can be reclaimed are all still one click away —
their own icon if you run separate items, their own tab if you run one.

### Also in this release

The drawn app icon now follows the **build's own flavour**, so a development
build stops wearing the shipping icon in its sidebar and splash. The About card
uses the real mark rather than a stand-in glyph.

### What changed since v1.0.17

- Paint the brand mark in the running build's own flavour colours, so a dev build stops wearing the shipping icon in its rail and splash, and use the real mark on the About card instead of a stand-in glyph. ([`bab73a0`](https://github.com/yunweneric/tidy/commit/bab73a09a7eb2c69f41ea936ab6d368405135910))
- Make the gauge popover about the machine and nothing else. The overview panel no longer carries the network rate, a clipboard teaser or the reclaimable totals — each already has its own menu bar item and its own tab — and shows memory pressure, swap and load average in their place, which the app has been sampling every two seconds and showing nowhere. ([`20ae406`](https://github.com/yunweneric/tidy/commit/20ae4066b64661c188c2632aaaa5ae0801b520f0))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.17...v1.0.18
