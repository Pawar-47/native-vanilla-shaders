#!/usr/bin/env python3
"""Compile every pack-owned core and post shader with glslangValidator.

Minecraft 26.3 uses ShaderC and its own resource/include pipeline. This check is
not a replacement for Minecraft runtime validation; it is an additional real
GLSL parser/type-check pass that catches syntax, overload and stage-local errors
that the repository's static checker cannot see.
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

INCLUDE_RE = re.compile(r'^\\s*#\\s*include\\s*[<"]([^>"]+)[>"]\\s*$', re.M)


def find_vanilla(root: Path):
    for child in (root / "reference" / "vanilla-stock").iterdir():
        if child.is_dir() and child.name.strip().lower() == "vanilla-stock":
            return child
    return None


def resolve_include(spec: str, root: Path, vanilla: Path):
    if ":" in spec:
        namespace, relative = spec.split(":", 1)
    else:
        namespace, relative = "minecraft", spec
    candidate = root / "assets" / namespace / "shaders" / "include" / relative
    if candidate.is_file():
        return candidate
    if namespace == "minecraft":
        candidate = vanilla / "include" / relative
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("cannot resolve shader include <%s>" % spec)


def expand_includes(path: Path, root: Path, vanilla: Path, stack=()):
    resolved = path.resolve()
    if resolved in stack:
        chain = " -> ".join(str(p.relative_to(root)) for p in stack + (resolved,))
        raise RuntimeError("cyclic shader include: " + chain)
    source = path.read_text(encoding="utf-8")

    def replace(match):
        spec = match.group(1)
        included = resolve_include(spec, root, vanilla)
        body = expand_includes(included, root, vanilla, stack + (resolved,))
        return "\\n// begin include <%s>\\n%s\\n// end include <%s>\\n" % (spec, body, spec)

    return INCLUDE_RE.sub(replace, source)


def variants_for(path: Path):
    name = path.name
    if name in ("terrain.vsh", "terrain.fsh"):
        return [(), ("MULTIDRAW_TERRAIN",), ("OIT_ALPHA_ONLY",),
                ("MULTIDRAW_TERRAIN", "OIT_ALPHA_ONLY")]
    if name in ("clouds.fsh", "position_color.fsh"):
        return [(), ("OIT_ALPHA_ONLY",)]
    return [()]


def compile_one(validator: str, source: str, stage: str, label: str, defines, tempdir: Path):
    suffix = ".vert" if stage == "vert" else ".frag"
    temporary = tempdir / (re.sub(r"[^A-Za-z0-9_.-]", "_", label) + suffix)
    temporary.write_text(source, encoding="utf-8")
    command = [validator, "-S", stage]
    command.extend("-D%s=1" % define for define in defines)
    command.append(str(temporary))
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print("FAILED: %s [%s]" % (label, ", ".join(defines) if defines else "default"))
        print(result.stdout)
        return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--validator", default="glslangValidator")
    args = parser.parse_args()
    validator = shutil.which(args.validator)
    if not validator:
        sys.exit("glslangValidator not found; install the glslang-tools package")

    root = args.root.resolve()
    vanilla = find_vanilla(root)
    if vanilla is None:
        sys.exit("the extracted Vanilla-stock reference directory is required for GLSL compilation")

    shader_dirs = [
        root / "assets" / "minecraft" / "shaders" / "core",
        root / "assets" / "nvs" / "shaders" / "post",
    ]
    sources = sorted(path for directory in shader_dirs if directory.is_dir()
                     for path in directory.rglob("*") if path.suffix in (".vsh", ".fsh"))
    if not sources:
        sys.exit("no pack-owned shader stages found")

    failures = []
    compiled = 0
    with tempfile.TemporaryDirectory(prefix="nvs-glsl-") as temp:
        tempdir = Path(temp)
        for path in sources:
            stage = "vert" if path.suffix == ".vsh" else "frag"
            try:
                expanded = expand_includes(path, root, vanilla)
            except Exception as error:
                failures.append((path, str(error)))
                continue
            for defines in variants_for(path):
                label = path.relative_to(root).as_posix()
                if not compile_one(validator, expanded, stage, label, defines, tempdir):
                    failures.append((path, "GLSL compilation failed for %r" % (defines,)))
                else:
                    compiled += 1

    if failures:
        for path, message in failures:
            print("ERROR: %s: %s" % (path.relative_to(root), message))
        sys.exit(1)
    print("GLSL syntax/type check passed: %d shader-stage variants compiled." % compiled)
    print("Note: this is glslang validation, not Minecraft 26.3 ShaderC or runtime validation.")


if __name__ == "__main__":
    main()
