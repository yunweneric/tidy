## 🧹 Tidy v1.0.9

| Download | For |
| --- | --- |
| `Tidy-1.0.9.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.9-macos.zip` | What the in-app updater downloads |

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

### What changed since v1.0.8

- Enhance README with download statistics section and clarify asset download metrics. Update app icons with new menu and GitHub icons. Improve landing navigation for touch devices with responsive height adjustments and a new navigation sheet for better user experience. ([`4f237c4`](https://github.com/yunweneric/tidy/commit/4f237c45d6f535892e8272ab829b08a9ba59d7ba))
- Refactor landing navigation for improved touch responsiveness and update GitHub icon with a star badge. Introduce new filled star icon for better visual clarity in the GitHub chip component. ([`5ac9c7d`](https://github.com/yunweneric/tidy/commit/5ac9c7d8443018f8c14cdaf5ffe8dd4c4293c0db))
- Implement AI usage features in menu bar settings, including new readout scope and window style options. Update related models and UI components to support per-provider usage tracking. Refactor menu bar preferences and popover handling to accommodate these changes. ([`f3592d1`](https://github.com/yunweneric/tidy/commit/f3592d1c24bcdf1448792a8f152fca1cf8f01ac5))
- Refactor permission section initialization to ensure service refresh occurs after the frame is built, preventing potential UI issues during rebuilds. This change enhances the handling of macOS permission requests and maintains silent operation until the request has been made. ([`ea3ba16`](https://github.com/yunweneric/tidy/commit/ea3ba16fba2a22e2503604d5117ba9fd5283f2d3))
- Update version number in pubspec.yaml to 1.0.9+10 for the next release. ([`f05a43d`](https://github.com/yunweneric/tidy/commit/f05a43deadeaa89b0e6fe4df62b77945c0772194))
- Add an update prompt to the sidebar; a chip pinned above Settings now follows the update check and carries the download, the install and the cancel inline, with a progress bar while the release is fetched and a red row when it fails. Hoisted the update bloc into the shell state so re-activating the window re-checks after a sleep, and fixed `?section=updates` so both the chip and the toast land on the Updates tab when Settings was already open on another one.

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.8...v1.0.9
