## 🧹 Tidy v1.0.16

| Download | For |
| --- | --- |
| `Tidy-1.0.16.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.16-macos.zip` | What the in-app updater downloads |

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

### Protection

The last big gap in the sidebar is filled. **Protection** answers three
questions about this Mac: what starts itself, what your browser extensions can
reach, and where your apps came from.

**It is not an antivirus, and it says so on the page.** Tidy has no list of
known-bad software and never downloads one. Everything here is something macOS
can prove about a file already on your Mac — whether it is signed, by whom,
whether the program it points at still exists, where it runs from, and which
browser downloaded it. Verdicts read "Not signed" and "Binary is missing", never
"malware". A quiet page is not a clean bill of health, and the page says that
too.

- **Startup items** — every launchd agent and daemon outside macOS's own, with
  the signature on the program each one runs. A missing binary, something
  running out of a temporary folder, or a file macOS will not let Tidy open all
  stand out. Anything Homebrew built is named as such rather than flagged, and
  any row can be settled so it stops being raised.
- **Browser extensions** — Chrome, Brave, Edge and Firefox. What each extension
  can reach, and whether it changes your search engine. "Can read every site" is
  shown but not treated as a problem: it is true of two in five extensions and
  is how ad blockers and password managers work.
- **Installed apps** — who signed each one, and which browser downloaded it and
  when. Checking an app's seal properly takes seconds, so it is a button on the
  row rather than part of the sweep.
- **Privacy traces** — the download history macOS keeps about you.

**What it does not do**, each said in the section it applies to: Safari is not
covered, because its extensions are App Store apps and its settings sit behind a
permission Tidy does not ask for. Saved Wi-Fi networks are readable only by an
administrator, and Tidy will not ask for your password to read a list. Browser
extensions are revealed and explained rather than removed, because Chrome
re-installs anything you delete underneath it.

### What changed since v1.0.15

- Move the launchd model and service into `core/` so Protection can read the same startup items Performance does, rather than growing a second plist reader and a second elevated-remove path. The channel name is unchanged; nothing native moved. ([`fd985c4`](https://github.com/yunweneric/tidy/commit/fd985c46acec12b5374d392a3888891c6ddbe5c7))
- Point Performance at the relocated launch-item service. No behaviour change. ([`82be4c9`](https://github.com/yunweneric/tidy/commit/82be4c9d67c3fb68ef41b412b225e7f9e914d0b8))
- Build Protection: what starts itself, what your browser extensions can reach, and where your apps came from. Reports only what macOS can prove locally — whether a thing is signed, by whom, whether its binary exists, where it runs from and which browser downloaded it. No list of known-bad software is consulted or downloaded, and the page says so. Startup items can be turned off or removed through the path that already existed for them; browser extensions are revealed and explained rather than deleted, because Chrome undoes that. Safari, saved Wi-Fi networks and recent-item contents are not covered, and each says why. ([`ca17275`](https://github.com/yunweneric/tidy/commit/ca17275947319879c2cfb0d464c1b18686e294c8))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.15...v1.0.16
