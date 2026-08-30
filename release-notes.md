## 🧹 Tidy v1.0.11

| Download | For |
| --- | --- |
| `Tidy-1.0.11.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.11-macos.zip` | What the in-app updater downloads |

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

### What changed since v1.0.10

- Add Claude plan limits to AI Usage; session and weekly allowances are now read from your Claude account and drawn as real percentage bars, with per-model weekly windows, on both the page and the menu bar popover. The AI Usage page now renders the same window rows the popover draws instead of its own session block, so the weekly window is finally visible there; derived views are computed once per sweep rather than on every frame; and a one-minute ticker keeps the countdowns and percentages live. ([`cd35072`](https://github.com/yunweneric/tidy/commit/cd3507219071e379dc3e405661d8c2dfadc88d69))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.10...v1.0.11
