## 🧹 Tidy v1.0.19

| Download | For |
| --- | --- |
| `Tidy-1.0.19.dmg` | A first install — drag Tidy to Applications |
| `Tidy-1.0.19-macos.zip` | What the in-app updater downloads |

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

### My Clutter is a real page

The sidebar entry that has said "coming soon" since the module list was drawn
now runs three sweeps over the folders where files quietly accumulate —
Downloads, Documents, Desktop, Pictures, Movies and Music. `~/Library` is left
out on purpose: what is in there is app-managed, not yours to weed.

**Large & old files.** Anything at least 500 MB that has not been touched in six
months, grouped by the folder it sits in. This is an inference about what you
probably no longer need, so nothing is pre-selected and every finding is marked
worth a look.

**Downloads.** Installers you have already run — `.dmg`, `.pkg`, `.mpkg` older
than 90 days, whatever their size, because the point of an installer was the one
install — and plain downloads over 50 MB that have sat for six months.

**Duplicates.** Byte-identical copies of the same file, found by size, then a
64 KB prefix hash, then a full SHA-256 of the files that still match.

### Duplicates that tell the truth about what they free

The easy version of a duplicate finder overstates what it can reclaim badly
enough to be a lie. Two files can be byte-identical and cost nothing to keep:

- A **hardlink** is two names for one set of blocks. Deleting one frees nothing.
- An **APFS clone** — what a Finder duplicate makes — is two files sharing every
  extent. Each reports its full size on disk, so a clone-blind scan can promise
  gigabytes that do not exist.

Tidy asks the kernel which bytes each copy actually owns and reports that. Clones
and hardlinks are listed, marked as sharing their storage, and counted as zero,
so the total on the button is the space you will really get back.

Every duplicate set keeps its oldest copy and leaves it off the list entirely —
so no sequence of clicks, Select All included, can remove the last copy of a
file. Bundles like `.app` and `.photoslibrary` are stepped over rather than
walked into, since a duplicated file inside one is not yours to delete on its
own.

Near-identical photos are not built yet, and the page says so.

### The coverage note says how much of a sweep is real

Smart Care and My Clutter both have names that sound more complete than they
are, and both now carry the same note: which checks run, which are still coming,
and a plain "4 of 7 checks built" so a clean result is not mistaken for a clean
bill of health. Pending checks are marked with a clock rather than a cross —
they have not failed, they have not shipped. It appears once per module and can
be dismissed for good.

### Fixes

- Module pages no longer overflow. A tall banner above the scan hero could push
  it past the bottom of a short window; the hero now scrolls instead.
- Smart Care no longer lists duplicates and large old files as unbuilt. They
  exist, and it points at My Clutter the way it already points at Protection.
