## 🧹 Tidy v1.0.13

| Download | For |
| --- | --- |
| `Tidy-1.0.13.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.13-macos.zip` | What the in-app updater downloads |

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

### Space Lens

The sidebar's last big gap is filled. **Space Lens** draws your disk as packed
circles — one folder at a time, each circle sized by *area* from the bytes it
actually occupies, so a sparse 64 GB `Docker.raw` draws the 8 GB that removing
it would really give back. Click a bubble to select it, double-click a folder
to open it, and reveal anything in Finder or move it to the Trash without
leaving the map.

It never walks the whole disk. Each folder is measured when you open it and
then kept, so drilling in costs one subtree, walking back out costs nothing,
and **Rescan** re-walks only the folder in front of you.

- Starts at **Home** or **Applications**. Not the boot volume: `/` descends into
  `/System`, which nobody may remove, and into `/Volumes`, where an attached
  backup drive turns the map into a twenty-minute stall.
- The map draws the forty largest and gathers the rest into one labelled bubble,
  so the panel beside it is where everything is listed exactly and unrounded.
- Folders macOS will not let Tidy read are counted and said out loud, rather
  than quietly making a total look smaller than it is.

### Also in this release

- The menu bar popover's clipboard list now **scrolls** instead of growing.
  The popover has a hard height cap, so rows past it were simply cut off with
  nothing to say they existed. The list holds sixty clips rather than fourteen,
  and still shrink-wraps so a short history stays short.

### What changed since v1.0.12

- Build Space Lens: the disk drawn as packed circles, one folder at a time, each sized by area from the allocated bytes it occupies. Never walks the whole disk — a level is measured on demand and kept, so drilling in costs one subtree, walking back up costs nothing and Rescan re-walks only the folder in front of you. Starts at Home or Applications, caps the map at forty bubbles with the tail gathered into one, lists everything exactly in the panel beside it, and can reveal in Finder or move to the Trash, recorded in Activity like every other removal. ([`e5f8016`](https://github.com/yunweneric/tidy/commit/e5f80169b37b40a8a37ec4bb2064db6fa099f161))
- Scroll the menu bar's clipboard list instead of growing the panel. The popover has a hard height cap, so rows past it were cut off with nothing to say they existed; the list is now bounded and scrollable and holds sixty clips rather than fourteen, still shrink-wrapping so a short history stays short. ([`9c1f3ee`](https://github.com/yunweneric/tidy/commit/9c1f3eee75bceafd8fc0e3437f2eebd0d994176b))

**Full changelog:** https://github.com/yunweneric/tidy/compare/v1.0.12...v1.0.13
