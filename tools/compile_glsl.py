#!/usr/bin/env python3
"""Run an additional GLSL syntax/type pass over pack-owned shader stages.

Minecraft 26.3 uses ShaderC and its own resource/include pipeline. glslang is
used here as a second parser, not as a replacement for Minecraft compilation or
in-game runtime testing.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile

INCLUDE_RE = re.compile(r'^\\s*#\\s*include\\s*[<"]([^>"]+)[>"]\\s*$', re.M)

# glslang's OpenGL frontend exposes gl_VertexID; Minecraft's ShaderC source
# uses the Vulkan-style gl_VertexIndex spelling for the same vertex index.
VERTEX_INDEX_COMPAT = "#define gl_VertexIndex gl_VertexID"


def find_vanilla(root: Path):
    directory = root / "reference" / "vanilla-stock"
    if not directory.is_dir():
        return None
    for child in directory.iterdir():
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


def add_glslang_compat(source: str):
    lines = source.splitlines()
    if not lines or not lines[0].lstrip().startswith("#version"):
        raise RuntimeError("shader must begin with #version")
    insert_at = 1
    while insert_at < len(lines) and lines[insert_at].lstrip().startswith("#extension"):
        insert_at += 1
    lines.insert(insert_at, VERTEX_INDEX_COMPAT)
    return "\\n".join(lines) + "\\n"


def oit_defines(coeff_count):
    return (
        "OIT=1",
        "OIT_COEFF_COUNT=%d" % coeff_count,
        "OIT_COEFF_ATTACHMENT_COUNT=%d" % (coeff_count // 4),
        "OIT_WAVELET_RANK=%d" % (coeff_count.bit_length() - 2),
    )


def variants_for(path: Path, source: str):
    variants = [()]
    if path.name == "rendertype_end_portal.fsh":
        return [("PORTAL_LAYERS=15",), ("PORTAL_LAYERS=16",)]

    uses_oit = "minecraft:oit.glsl" in source or "OIT_ALPHA_ONLY" in source or "OIT_ACCUMULATE" in source
    if uses_oit:
        for count in (8, 16):
            base = oit_defines(count)
            variants.extend([
                base + ("OIT_ALPHA_ONLY=1", "OIT_DEPTH_BOUNDS=1"),
                base + ("OIT_ALPHA_ONLY=1", "OIT_TRANSMITTANCE=1"),
                base + ("OIT_ACCUMULATE=1",),
                base + ("OIT_ACCUMULATE=1", "OIT_ADDITIVE=1"),
            ])
    return variants


def compile_one(validator, source, stage, label, defines, tempdir):
    suffix = ".vert" if stage == "vert" else ".frag"
    temporary = tempdir / (re.sub(r"[^A-Za-z0-9_.-]", "_", label) + suffix)
    temporary.write_text(source, encoding="utf-8")
    command = [validator, "-l", "-S", stage]
    for define in defines:
        command.append("-D" + define)
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
                expanded = add_glslang_compat(expanded)
            except Exception as error:
                failures.append((path, str(error)))
                continue
            for defines in variants_for(path, path.read_text(encoding="utf-8")):
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
    print("This is glslang validation, not Minecraft 26.3 ShaderC or runtime validation.")


if __name__ == "__main__":
    main()
