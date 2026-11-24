#!/usr/bin/env python3
"""One-time extractor for the Minecraft vanilla shader reference archive.

Usage:
    python tools/extract_vanilla_reference.py

The archive is extracted beneath reference/vanilla-stock/. This directory is
reference material only and is never copied into the distributable shader pack.
The script is idempotent: after a successful run it writes a marker and exits
without extracting again unless --force is supplied.
"""
from __future__ import annotations

import argparse
import stat
import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile

REPO_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_DIR = REPO_ROOT / "reference" / "vanilla-stock"
MARKER = REFERENCE_DIR / ".vanilla-stock-extracted"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true",
                        help="extract again even if the completion marker exists")
    args = parser.parse_args()

    if MARKER.exists() and not args.force:
        print(f"Already extracted (marker: {MARKER}). Nothing to do.")
        return 0

    archives = sorted(p for p in REFERENCE_DIR.glob("*.zip") if p.is_file())
    if len(archives) != 1:
        print(f"Expected exactly one ZIP in {REFERENCE_DIR}; found {len(archives)}.",
              file=sys.stderr)
        return 2

    archive = archives[0]
    try:
        with ZipFile(archive) as zf:
            entries = zf.infolist()
            if len(entries) > 20000:
                raise ValueError("archive exceeds 20,000 entries")
            if sum(e.file_size for e in entries) > 500 * 1024 * 1024:
                raise ValueError("uncompressed archive exceeds 500 MiB")

            root = REFERENCE_DIR.resolve()
            for entry in entries:
                target = (REFERENCE_DIR / entry.filename).resolve()
                if target != root and root not in target.parents:
                    raise ValueError(f"unsafe archive path: {entry.filename}")
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError(f"symbolic link is not allowed: {entry.filename}")
                if target == (REFERENCE_DIR / "README.md").resolve():
                    raise ValueError("archive may not overwrite README.md")
            zf.extractall(REFERENCE_DIR)

    except (BadZipFile, OSError, ValueError) as exc:
        print(f"Extraction failed: {exc}", file=sys.stderr)
        return 1

    extracted_count = sum(
        1 for p in REFERENCE_DIR.rglob("*")
        if p.is_file() and p != archive and p not in (MARKER, REFERENCE_DIR / "README.md")
    )
    if extracted_count == 0:
        print("No reference files were extracted; no marker written.", file=sys.stderr)
        return 1

    MARKER.write_text(
        f"Extracted from {archive.name}; files present: {extracted_count}. "
        "Reference-only; excluded from distributable builds.\n",
        encoding="utf-8",
    )
    print(f"Extracted reference archive: {archive.name}")
    print(f"Reference files present: {extracted_count}")
    print("Done. This script will not extract again unless --force is used.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
