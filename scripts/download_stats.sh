#!/usr/bin/env bash
#
# Snapshot how many times each release asset has been downloaded.
#
# GitHub counts every asset download for free and forever, but only reports a
# running total — there is no "downloads last week" anywhere in the API. So the
# totals are sampled on a schedule and the differences are the answer. See
# `.github/workflows/download-stats.yml` for the schedule.
#
# Usage:
#   ./scripts/download_stats.sh                 # print the current counts
#   ./scripts/download_stats.sh --append        # ... and record them in the CSV
#   ./scripts/download_stats.sh --csv PATH      # use a different CSV
#   ./scripts/download_stats.sh --repo o/n      # a repository other than this one
#
# Reading the numbers — the three assets do not mean the same thing:
#
#   DMG    Closest to "a person decided to install Tidy". Only humans fetch it,
#          from the Releases page or the landing page's download button.
#   ZIP    New installs *plus* every in-app update: the updater downloads the
#          zip to install it (`core/updates/github_release_client.dart`). An
#          install count, not a people count.
#   SUMS   Fetched while *checking* for an update, not only when installing one
#          — so it tracks roughly with active installs rather than new ones.
#
# None of them deduplicate. Crawlers, mirrors and link previewers all count, and
# one person downloading twice counts twice.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CSV="metrics/downloads.csv"
APPEND=false
REPO="${GITHUB_REPOSITORY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --append) APPEND=true ;;
    --csv) CSV="${2:?--csv needs a path}"; shift ;;
    --repo) REPO="${2:?--repo needs owner/name}"; shift ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if ! command -v gh >/dev/null 2>&1; then
  echo "This needs the GitHub CLI (brew install gh), authenticated with 'gh auth login'." >&2
  exit 1
fi

# `GITHUB_REPOSITORY` is set for us inside Actions; locally, ask gh which
# repository this checkout belongs to rather than hard-coding a slug that would
# be wrong in a fork.
if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

# Whole seconds, UTC. A date alone would collapse two runs on one day into
# rows that look like a flat week rather than two samples.
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# tag <TAB> published <TAB> asset <TAB> count, newest release first.
ROWS="$(
  gh api "repos/$REPO/releases" --paginate -q '
    .[] | . as $r | $r.assets[]
    | [$r.tag_name, ($r.published_at | split("T")[0]), .name, .download_count]
    | @tsv
  '
)"

if [[ -z "$ROWS" ]]; then
  echo "No published releases with assets on $REPO — nothing to count yet."
  exit 0
fi

# ─── The table ──────────────────────────────────────────────────────────────
#
# One row per release with the three assets as columns, because that is the
# shape the question comes in: "how did v1.0.8 do?", not "how did this file do?".
# Anything unrecognised is summed into OTHER rather than dropped — a release
# that starts shipping a fourth artifact should show up, not vanish.

# The previous snapshot, so the table can show movement rather than a total
# that means nothing without one. Absent on the first run, which is fine.
#
# Written to a file rather than passed with `awk -v`: BSD awk runs a `-v` value
# through escape processing and chokes on the embedded newlines, so a multi-row
# snapshot has to arrive as an input rather than as a variable.
PREV_AT=""
PREV_FILE="$(mktemp "${TMPDIR:-/tmp}/tidy-downloads.XXXXXX")"
trap 'rm -f "$PREV_FILE"' EXIT

if [[ -f "$CSV" ]]; then
  PREV_AT="$(awk -F, 'NR > 1 { print $1 }' "$CSV" | sort -u | tail -n 1)"
  if [[ -n "$PREV_AT" ]]; then
    awk -F, -v at="$PREV_AT" 'NR > 1 && $1 == at { print $2 "\t" $4 "\t" $5 }' "$CSV" > "$PREV_FILE"
  fi
fi

printf '%s — %s\n' "$REPO" "$NOW"
if [[ -n "$PREV_AT" ]]; then
  printf 'Change is since the previous snapshot, %s.\n' "$PREV_AT"
else
  printf 'First snapshot: no previous sample to compare against yet.\n'
fi
printf '\n'

printf '%s\n' "$ROWS" | awk -F'\t' -v prevfile="$PREV_FILE" '
  function kind(name) {
    if (name ~ /\.dmg$/) return "dmg"
    if (name ~ /\.zip$/) return "zip"
    if (tolower(name) == "sha256sums.txt") return "sums"
    return "other"
  }
  # A count, plus how far it has moved since the previous sample. The delta is
  # the reason this file exists, so it sits next to the number rather than in a
  # second table underneath.
  function cell(key,   value, delta) {
    value = now[key] + 0
    if (!haveprev) return sprintf("%8d", value)
    delta = value - (was[key] + 0)
    return sprintf("%8d%-6s", value, delta > 0 ? sprintf(" +%d", delta) : "")
  }
  BEGIN {
    while ((getline line < prevfile) > 0) {
      if (line == "") continue
      split(line, f, "\t")
      was[f[1] SUBSEP kind(f[2])] += f[3]
      was["TOTAL" SUBSEP kind(f[2])] += f[3]
      haveprev = 1
    }
    close(prevfile)
  }
  {
    tag = $1
    published[tag] = $2
    k = kind($3)
    if (!(tag in seen)) { order[++tags] = tag; seen[tag] = 1 }
    now[tag SUBSEP k] += $4
    now["TOTAL" SUBSEP k] += $4
    if (k == "other") anyother = 1
  }
  # The column heading, padded to line its text up with the digits underneath
  # rather than with the delta that trails them.
  function head(name) {
    return haveprev ? sprintf("%8s%-6s", name, "") : sprintf("%8s", name)
  }
  function trimmed(line) {
    sub(/[ \t]+$/, "", line)
    return line
  }
  END {
    line = sprintf("%-12s %-12s %s %s %s", "TAG", "PUBLISHED", head("DMG"), head("ZIP"), head("SUMS"))
    if (anyother) line = line " " head("OTHER")
    print trimmed(line)

    for (i = 1; i <= tags; i++) {
      t = order[i]
      line = sprintf("%-12s %-12s %s %s %s", t, published[t],
        cell(t SUBSEP "dmg"), cell(t SUBSEP "zip"), cell(t SUBSEP "sums"))
      if (anyother) line = line " " cell(t SUBSEP "other")
      print trimmed(line)
    }

    print ""
    line = sprintf("%-12s %-12s %s %s %s", "TOTAL", "all releases",
      cell("TOTAL" SUBSEP "dmg"), cell("TOTAL" SUBSEP "zip"), cell("TOTAL" SUBSEP "sums"))
    if (anyother) line = line " " cell("TOTAL" SUBSEP "other")
    print trimmed(line)
  }
'

# ─── The CSV ────────────────────────────────────────────────────────────────
#
# Long format, one row per asset per sample, appended and never rewritten: the
# file is the history, so an edit to an old row is a lie about the past.
#
# Every asset is written on every run, including releases whose counts have not
# moved in months. Recording only the changes would halve the file and lose the
# thing that makes it trustworthy — with a full sample each time, a week with no
# rows is a week the job did not run, not a week nobody downloaded anything.
if [[ "$APPEND" == true ]]; then
  mkdir -p "$(dirname "$CSV")"
  if [[ ! -f "$CSV" ]]; then
    echo "snapshot_utc,tag,published,asset,downloads" > "$CSV"
  fi
  printf '%s\n' "$ROWS" | awk -F'\t' -v at="$NOW" 'BEGIN { OFS = "," } { print at, $1, $2, $3, $4 }' >> "$CSV"
  printf '\nAppended %d rows to %s\n' "$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')" "$CSV"
fi
