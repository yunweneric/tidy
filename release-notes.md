## 🧹 Tidy v1.0.15

| Download | For |
| --- | --- |
| `Tidy-1.0.15.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.15-macos.zip` | What the in-app updater downloads |

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

### What changed since v1.0.14

- Update check interval to 30 minutes and improve update check logic ([`12107da`](https://github.com/yunweneric/tidy/commit/12107da19a6312b0369916687f9698734148eb02))
- Update version number in pubspec.yaml to 1.0.15+16 for the next release. ([`ea7f6e5`](https://github.com/yunweneric/tidy/commit/ea7f6e52fb6a04ed8163907c564ef5a281423a35))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.14...v1.0.15
