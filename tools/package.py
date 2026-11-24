#!/usr/bin/env python3
"""Assemble the installable pack.

The repository root is not the pack: it also holds the vanilla reference folder
(`Vanilla-stock /`), the benchmark shaderpack (`Good working shader/`, whose
licence does **not** permit redistribution) and this tooling. Minecraft ignores
paths it does not know, so dropping the whole repository into `resourcepacks/`
would appear to work — and would redistribute material that must not be
redistributed, and ship tens of megabytes of source that the game never reads.

This script copies exactly what the pack is into `dist/`:

    dist/Native Vanilla Shaders/
        pack.mcmeta
        assets/          the shaders, the includes and the post effects
        MANIFEST/        provenance
        *.md             the documentation

and, with --zip, a `.zip` with `pack.mcmeta` at its archive root, which is the
form Minecraft expects for a zipped pack.

Usage:
    python3 tools/package.py            # build dist/Native Vanilla Shaders/
    python3 tools/package.py --zip      # also build the .zip
"""

import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACK_NAME = "Native Vanilla Shaders"
VERSION = "1.0.0"
MC_VERSION = "26.3"

# Everything that makes up the pack, relative to the repository root.
INCLUDE_PATHS = [
    "pack.mcmeta",
    "assets",
    "MANIFEST",
    "README.md",
    "INSTALLATION.md",
    "ARCHITECTURE.md",
    "FEATURE_MATRIX.md",
    "COMPATIBILITY.md",
    "LIMITATIONS.md",
    "TESTING.md",
    "CHANGELOG.md",
]

# Folders that must never end up inside the pack.
FORBIDDEN_TOP_LEVEL = [
    "Vanilla-stock ",
    "Vanilla-stock",
    "Good working shader",
    ".research",
    "tools",
    "dist",
]

SKIP_SUFFIXES = (".pyc",)
SKIP_DIRS = {"__pycache__", ".git"}


def copy_tree(source, destination):
    for base, dirs, names in os.walk(source):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        rel = os.path.relpath(base, source)
        target = os.path.join(destination, rel) if rel != "." else destination
        os.makedirs(target, exist_ok=True)
        for name in names:
            if name.endswith(SKIP_SUFFIXES):
                continue
            shutil.copy2(os.path.join(base, name), os.path.join(target, name))


def main(argv):
    build_zip = "--zip" in argv
    dist = os.path.join(ROOT, "dist")
    stage = os.path.join(dist, PACK_NAME)

    if os.path.isdir(stage):
        shutil.rmtree(stage)
    os.makedirs(stage, exist_ok=True)

    missing = []
    for entry in INCLUDE_PATHS:
        source = os.path.join(ROOT, entry)
        if not os.path.exists(source):
            missing.append(entry)
            continue
        destination = os.path.join(stage, entry)
        if os.path.isdir(source):
            copy_tree(source, destination)
        else:
            shutil.copy2(source, destination)

    if missing:
        print("error: missing from the repository: %s" % ", ".join(missing))
        return 1

    # Never let a reference folder or the tooling travel with the pack.
    for name in os.listdir(stage):
        if name in FORBIDDEN_TOP_LEVEL:
            shutil.rmtree(os.path.join(stage, name), ignore_errors=True)
            print("removed %r from the staged pack" % name)

    if not os.path.isfile(os.path.join(stage, "pack.mcmeta")):
        print("error: pack.mcmeta did not make it into the staged pack")
        return 1

    count = sum(len(files) for _base, _dirs, files in os.walk(stage))
    print("built dist/%s (%d files)" % (PACK_NAME, count))

    if build_zip:
        archive = os.path.join(dist, "%s %s - MC %s.zip" % (PACK_NAME, VERSION, MC_VERSION))
        if os.path.exists(archive):
            os.remove(archive)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as handle:
            for base, dirs, names in os.walk(stage):
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
                for name in sorted(names):
                    full = os.path.join(base, name)
                    # pack.mcmeta has to sit at the archive root, not in a folder.
                    handle.write(full, os.path.relpath(full, stage))
        print("built dist/%s" % os.path.basename(archive))

    print()
    print("Install: put dist/%s/ in .minecraft/resourcepacks/," % PACK_NAME)
    print("or put the .zip there directly. Do not copy the repository root.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
