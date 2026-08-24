#!/usr/bin/env python3
"""Register a Swift source file with the Runner target in project.pbxproj.

Flutter's macOS project lists every source file explicitly in four places, so a
new file that isn't registered simply never compiles — and the failure looks
like a missing symbol rather than a missing file. This adds all four entries.

Usage:
    scripts/add_swift_file.py MenuBarController.swift SystemChannel.swift
    scripts/add_swift_file.py --check          # list registered sources

Paths are relative to macos/Runner/. Already-registered files are skipped, so
the script is safe to re-run.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PBXPROJ = REPO / "macos" / "Runner.xcodeproj" / "project.pbxproj"

# The Runner group that holds AppDelegate.swift, and the Runner target's
# Sources phase. Anchoring on AppDelegate keeps us independent of the exact
# UUIDs Flutter generated.
ANCHOR = "AppDelegate.swift"


def object_id(seed: str) -> str:
    """A stable, unique 24-hex-char id. Xcode only requires uniqueness."""
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def registered(text: str) -> list[str]:
    return sorted(set(re.findall(r"/\* ([A-Za-z0-9_+\-]+\.swift) in Sources \*/", text)))


def add(text: str, name: str) -> tuple[str, bool]:
    if f"/* {name} in Sources */" in text:
        return text, False

    file_ref = object_id(f"fileRef:{name}")
    build_file = object_id(f"buildFile:{name}")

    # 1. PBXBuildFile — anchor on the existing AppDelegate build file line.
    text = re.sub(
        r"(\n\t\t[0-9A-F]{24} /\* %s in Sources \*/ = \{isa = PBXBuildFile;[^\n]*\n)" % ANCHOR,
        lambda m: m.group(1)
        + f"\t\t{build_file} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};\n",
        text,
        count=1,
    )

    # 2. PBXFileReference
    text = re.sub(
        r"(\n\t\t[0-9A-F]{24} /\* %s \*/ = \{isa = PBXFileReference;[^\n]*\n)" % ANCHOR,
        lambda m: m.group(1)
        + f'\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n',
        text,
        count=1,
    )

    # 3. Group children
    text = re.sub(
        r"(\n\t\t\t\t[0-9A-F]{24} /\* %s \*/,\n)" % ANCHOR,
        lambda m: m.group(1) + f"\t\t\t\t{file_ref} /* {name} */,\n",
        text,
        count=1,
    )

    # 4. Sources build phase
    text = re.sub(
        r"(\n\t\t\t\t[0-9A-F]{24} /\* %s in Sources \*/,\n)" % ANCHOR,
        lambda m: m.group(1) + f"\t\t\t\t{build_file} /* {name} in Sources */,\n",
        text,
        count=1,
    )

    if f"/* {name} in Sources */," not in text:
        raise SystemExit(f"Could not splice {name} into the Sources phase — pbxproj layout changed?")
    return text, True


def main(argv: list[str]) -> int:
    text = PBXPROJ.read_text()

    if not argv or argv[0] == "--check":
        print("\n".join(registered(text)))
        return 0

    changed = False
    for name in argv:
        name = Path(name).name
        if not (REPO / "macos" / "Runner" / name).exists():
            print(f"warning: macos/Runner/{name} does not exist yet", file=sys.stderr)
        text, did = add(text, name)
        print(f"{'added  ' if did else 'present'} {name}")
        changed |= did

    if changed:
        PBXPROJ.write_text(text)
        print(f"\nwrote {PBXPROJ.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
