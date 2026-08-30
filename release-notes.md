## 🧹 Tidy v1.0.12

| Download | For |
| --- | --- |
| `Tidy-1.0.12.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.12-macos.zip` | What the in-app updater downloads |

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

### What changed since v1.0.11

- Integrate Cleanup module and Developer Junk module into service locator. Update CleanupPage to reflect new cleanup features and improve UI messaging. Modify MenuBarPrefs to clarify surface visibility logic and enhance menu bar functionality. Refactor related components for better integration and user experience. ([`9f037d5`](https://github.com/yunweneric/tidy/commit/9f037d5aed48d6e96ba3eb63d29c50b09ab63101))
- Update app router to replace ComingSoonPage with ActivityPage for the activity destination. Modify AppDestination enum to reflect the new grouping and description for the activity section, enhancing clarity on its purpose within the app. ([`67251a2`](https://github.com/yunweneric/tidy/commit/67251a292463545148e9b3686028ffc879462f71))
- Update version number in pubspec.yaml to 1.0.12+13 for the next release. ([`e21a6a0`](https://github.com/yunweneric/tidy/commit/e21a6a020f8c78b13084f56d4d64442159caac6f))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.11...v1.0.12
