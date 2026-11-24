#!/usr/bin/env python3
"""Static checks for the Native Vanilla Shaders pack.

This cannot compile GLSL: the game compiles with shaderc to SPIR-V and there is
no shaderc here. What it does instead is verify the rules that a broken pack
fails on, so that a mistake is caught here rather than in the game, where a
single failing core shader makes Minecraft drop every selected resource pack.

Checks:
  1. structure        - the files a pack needs, and none of the files an
                        Iris/OptiFine pack has (the pack must load with no
                        shader loader at all).
  2. declarations     - every uniform block and sampler a replaced program
                        declares is one its pipelines actually provide, in every
                        define variant it is compiled with.
  3. include          - every #include resolves; no include has a #version.
  4. varyings         - every fragment input has a vertex output at the same
                        location, in every program the game links with it.
  5. symbols          - every nvs_ function and NVS_ macro the pack uses is
                        defined somewhere in the pack (catches typos).
  6. post effects     - the JSON chains are valid, their targets and shaders
                        exist, and their shaders declare only what a post pass
                        is given.
  7. glsl hygiene     - version first, separate shader objects, balanced
                        preprocessor and braces, layout on every varying.

Usage:
    python3 tools/check_pack.py [pack-dir]

Exit code 0 means every check passed.
"""

import json
import os
import re
import sys

# --------------------------------------------------------------------------
# What each replaced program's pipelines provide, from the 26.3 reference.
#
# "always"    : provided by every pipeline of the program
# "conditional": provided only under the given guard, and the declaration in the
#                pack must sit inside that guard
# --------------------------------------------------------------------------
PROGRAM_UNIFORMS = {
    "sky.vsh": {
        "always": {"Fog", "Globals", "DynamicTransforms", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "sky.fsh": {
        "always": {"Fog", "Globals", "DynamicTransforms", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "stars.vsh": {
        "always": {"Globals", "DynamicTransforms", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "stars.fsh": {
        "always": {"Globals", "DynamicTransforms", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "position_tex.vsh": {
        "always": {"DynamicTransforms", "Globals", "Projection"},
        "samplers": {"Sampler0"},
        "conditional": {},
    },
    "position_tex.fsh": {
        "always": {"DynamicTransforms", "Globals", "Projection"},
        "samplers": {"Sampler0"},
        "conditional": {},
    },
    "position_color.vsh": {
        "always": {"DynamicTransforms", "Globals", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "position_color.fsh": {
        "always": {"DynamicTransforms", "Globals", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "debug_point.vsh": {
        "always": {"DynamicTransforms", "Globals", "Projection"},
        "samplers": set(),
        "conditional": {},
    },
    "clouds.vsh": {
        "always": {"CloudInfo", "DynamicTransforms", "Fog", "Globals", "Projection"},
        "samplers": {"CloudFaces"},
        "conditional": {},
    },
    "clouds.fsh": {
        "always": {"CloudInfo", "DynamicTransforms", "Fog", "Globals", "Projection"},
        "samplers": {"CloudFaces"},
        "conditional": {},
    },
    "particle.vsh": {
        "always": {"Fog", "Globals", "DynamicTransforms", "Projection"},
        "samplers": {"Sampler2"},
        "conditional": {},
    },
    "terrain.vsh": {
        "always": {"Fog", "Globals", "Projection", "TerrainUniform"},
        "samplers": {"Sampler0"},
        "conditional": {
            "Sampler2": ("OIT_ALPHA_ONLY", "not defined"),
            "ChunkSection": ("MULTIDRAW_TERRAIN", "not defined"),
        },
    },
    "terrain.fsh": {
        "always": {"Fog", "Globals", "Projection", "TerrainUniform"},
        "samplers": {"Sampler0"},
        "conditional": {
            "Sampler2": ("OIT_ALPHA_ONLY", "not defined"),
            "ChunkSection": ("MULTIDRAW_TERRAIN", "not defined"),
        },
    },
    "lightmap.fsh": {
        "always": {"Globals", "LightmapInfo"},
        "samplers": set(),
        "conditional": {},
    },
}

# Post passes get exactly: Globals, SamplerInfo, one <sampler_name>Sampler per
# input, and the blocks listed in the pass's "uniforms". Anything else fails
# with "Unable to find shader defined uniform".
POST_ALLOWED_BLOCKS = {"Globals", "SamplerInfo"}

# Which vertex programs each replaced fragment program is linked with. From the
# reference: position_color.fsh is shared with debug_point.vsh.
FRAGMENT_PARTNERS = {
    "sky.fsh": ["sky.vsh"],
    "stars.fsh": ["stars.vsh"],
    "position_tex.fsh": ["position_tex.vsh"],
    "position_color.fsh": ["position_color.vsh", "debug_point.vsh"],
    "clouds.fsh": ["clouds.vsh"],
    "particle.fsh": ["particle.vsh"],
    "terrain.fsh": ["terrain.vsh"],
    "lightmap.fsh": ["screenquad.vsh"],
    "bloom.fsh": ["fullscreen.vsh"],
    "composite.fsh": ["fullscreen.vsh"],
    "copy.fsh": ["fullscreen.vsh"],
    "fxaa.fsh": ["fullscreen.vsh"],
}

REQUIRED_FILES = [
    "pack.mcmeta",
    "README.md",
    "INSTALLATION.md",
    "ARCHITECTURE.md",
    "FEATURE_MATRIX.md",
    "COMPATIBILITY.md",
    "LIMITATIONS.md",
    "TESTING.md",
    "CHANGELOG.md",
    "MANIFEST/vanilla-hashes.json",
    "MANIFEST/modified-files.json",
    "MANIFEST/licensing.md",
    "assets/minecraft/post_effect/end_of_frame.json",
]

# Files that belong to a loader-based pack and must never appear here: if one of
# these exists the pack is not a pure vanilla resource pack any more.
FORBIDDEN_NAMES = re.compile(
    r"^(gbuffers_.*|shadowcomp.*|deferred.*|composite\d*\.[a-z]+|"
    r"final\.[a-z]+|prepare\.[a-z]+|dh_terrain\..*|dh_water\..*|"
    r"voxy.*|clrwl_.*)$"
)
FORBIDDEN_DIR_HINTS = ("/world0/", "/world-1/", "/world1/", "/dimension/")

DECL_RE = re.compile(
    r"^\s*(?:layout\s*\([^)]*\)\s*)?"
    r"((?:(?:flat|noperspective|smooth|centroid|invariant|highp|mediump|lowp)\s+)*)"
    r"(in|out)\s+([A-Za-z_][\w]*)\s+([A-Za-z_][\w]*)\s*;"
)
LOC_RE = re.compile(r"layout\s*\(\s*location\s*=\s*(\d+)\s*\)")
INCLUDE_RE = re.compile(r'#include\s*[<"]([^>"]+)[>"]')
BLOCK_RE = re.compile(r"^\s*(?:layout\s*\([^)]*\)\s*)?uniform\s+([A-Za-z_][\w]*)\s*\{")
SAMPLER_RE = re.compile(r"^\s*uniform\s+(?:sampler\w+|isampler\w+|usampler\w+)\s+([A-Za-z_][\w]*)\s*;")
PLAIN_UNIFORM_RE = re.compile(r"^\s*uniform\s+(?!sampler|isampler|usampler)(?!\w+\s*\{)[A-Za-z_][\w]*\s+[A-Za-z_][\w]*\s*;")


class Report:
    def __init__(self):
        self.errors = []
        self.notes = []

    def fail(self, check, where, message):
        self.errors.append((check, where, message))

    def note(self, message):
        self.notes.append(message)


def find_vanilla(root):
    # The user-supplied archive is stored under reference/vanilla-stock/, and
    # its extracted directory intentionally retains the source ZIP's trailing
    # space. Also accept a top-level folder for older local checkouts.
    for parent in (os.path.join(root, "reference", "vanilla-stock"), root):
        if not os.path.isdir(parent):
            continue
        for name in sorted(os.listdir(parent)):
            if name.strip().lower() == "vanilla-stock" and os.path.isdir(os.path.join(parent, name)):
                return os.path.join(parent, name)
    return None


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def pack_files(root):
    result = []
    for base, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in
                   ("Vanilla-stock ", "tools", "MANIFEST", "Good working shader")]
        for name in names:
            result.append(os.path.join(base, name))
    return result


# --------------------------------------------------------------------------
# 1. structure
# --------------------------------------------------------------------------
def check_structure(root, report):
    for rel in REQUIRED_FILES:
        if not os.path.isfile(os.path.join(root, rel)):
            report.fail("structure", rel, "required file is missing")

    meta_path = os.path.join(root, "pack.mcmeta")
    if os.path.isfile(meta_path):
        try:
            meta = json.loads(read(meta_path))
        except ValueError as error:
            report.fail("structure", "pack.mcmeta", "not valid JSON: %s" % error)
        else:
            pack = meta.get("pack", {})
            if pack.get("min_format") != 97 or pack.get("max_format") != 97:
                report.fail("structure", "pack.mcmeta",
                            "26.3 needs min_format and max_format 97, found %r/%r"
                            % (pack.get("min_format"), pack.get("max_format")))

    for path in pack_files(root):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        name = os.path.basename(path)
        # Loader stages are only forbidden at the root of a shaderpack's
        # shaders/ tree. A namespaced native post shader such as
        # assets/nvs/shaders/post/composite.fsh is valid and must not be
        # confused with Iris' root-level composite.fsh stage.
        parts = rel.split("/")
        shader_positions = [i for i, part in enumerate(parts) if part == "shaders"]
        if shader_positions:
            tail = parts[shader_positions[-1] + 1:]
            if name.endswith(".properties"):
                report.fail("structure", rel, "shaderpack .properties configuration is not a vanilla resource-pack feature")
            elif len(tail) == 1 and FORBIDDEN_NAMES.match(name):
                report.fail("structure", rel, "this root-level stage belongs to a loader-based shaderpack, not vanilla")
        for hint in FORBIDDEN_DIR_HINTS:
            if hint in "/" + rel:
                report.fail("structure", rel, "dimension/world shader folders are a loader feature")

    shader_root = os.path.join(root, "assets", "minecraft", "shaders")
    if os.path.isdir(shader_root):
        for name in sorted(os.listdir(shader_root)):
            if os.path.isfile(os.path.join(shader_root, name)) and name.lower().endswith((".vsh", ".fsh", ".glsl")):
                report.fail("structure", "assets/minecraft/shaders/" + name,
                            "vanilla reads core/, include/ and post/; a file at the shaders root is never compiled")


# --------------------------------------------------------------------------
# 2, 6. per-file declarations and GLSL hygiene
# --------------------------------------------------------------------------
def preprocessor_guards(lines):
    """For every line, the stack of enclosing preprocessor conditions."""
    stack = []
    guards = []
    for line in lines:
        stripped = line.strip()
        guards.append(list(stack))
        if re.match(r"#\s*if", stripped):
            stack.append(stripped)
        elif re.match(r"#\s*else", stripped) and stack:
            stack[-1] = "else:" + stack[-1]
        elif re.match(r"#\s*endif", stripped) and stack:
            stack.pop()
    return guards


def guard_allows(guards, token, sense):
    for guard in reversed(guards):
        if token in guard:
            if sense == "not defined":
                compact = guard.replace(" ", "")
                return "ifndef" in guard or "!defined" in compact
            return True
    return False


def check_glsl_hygiene(root, rel, text, report, is_include):
    lines = text.splitlines()
    if not is_include:
        first = None
        for index, line in enumerate(lines):
            if line.strip():
                first = (index, line.strip())
                break
        if first is None:
            report.fail("glsl", rel, "empty file")
            return
        if not first[1].startswith("#version"):
            report.fail("glsl", rel, "#version must be the first thing in the file")
        if "GL_ARB_separate_shader_objects" not in text:
            report.fail("glsl", rel, "missing #extension GL_ARB_separate_shader_objects : require")
    elif re.search(r"^\s*#\s*version", text, re.M):
        report.fail("glsl", rel, "an include may not contain #version")

    if "moj_import" in text:
        report.fail("glsl", rel, "#moj_import was removed in 26.3; use #include")

    if not is_include:
        code = strip_comments(text)
        for opener, closer, label in (("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")):
            if code.count(opener) != code.count(closer):
                report.fail("glsl", rel, "unbalanced %s: %d vs %d"
                            % (label, code.count(opener), code.count(closer)))

    depth = 0
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if re.match(r"#\s*if", stripped):
            depth += 1
        elif re.match(r"#\s*endif", stripped):
            depth -= 1
            if depth < 0:
                report.fail("glsl", rel, "line %d: #endif without #if" % number)
                depth = 0
        if PLAIN_UNIFORM_RE.match(stripped):
            report.fail("glsl", rel,
                        "line %d: plain uniforms outside a block are not allowed in 26.3" % number)
    if depth != 0:
        report.fail("glsl", rel, "%d unclosed preprocessor condition(s)" % depth)


def check_declarations(rel_base, text, report, rel):
    spec = PROGRAM_UNIFORMS.get(rel_base)
    if spec is None:
        return
    lines = text.splitlines()
    guards = preprocessor_guards(lines)

    for number, line in enumerate(lines, 1):
        block = BLOCK_RE.match(line)
        sampler = SAMPLER_RE.match(line)
        name = None
        kind = None
        if block:
            name, kind = block.group(1), "block"
        elif sampler:
            name, kind = sampler.group(1), "sampler"

        if name is None:
            continue

        if kind == "sampler":
            allowed = name in spec["samplers"] or name in spec["conditional"]
        else:
            allowed = name in spec["always"] or name in spec["conditional"]

        if not allowed:
            report.fail("declarations", rel,
                        "line %d: %s %r is not provided to %s by any of its pipelines"
                        % (number, kind, name, rel_base))
            continue

        if name in spec["conditional"]:
            token, sense = spec["conditional"][name]
            if not guard_allows(guards[number - 1], token, sense):
                report.fail("declarations", rel,
                            "line %d: %r must be declared under #ifndef %s"
                            % (number, name, token))


# --------------------------------------------------------------------------
# 3. includes
# --------------------------------------------------------------------------
def resolve_include(spec, root, vanilla):
    if ":" not in spec:
        namespace, path = "minecraft", spec
    else:
        namespace, path = spec.split(":", 1)
    rel = os.path.join("assets", namespace, "shaders", "include", path)
    if os.path.isfile(os.path.join(root, rel)):
        return "pack"
    if vanilla and os.path.isfile(os.path.join(vanilla, "include", os.path.basename(path))):
        return "vanilla"
    return None


def check_includes(root, vanilla, report):
    for base, _dirs, names in os.walk(os.path.join(root, "assets")):
        for name in names:
            if not name.endswith((".vsh", ".fsh", ".glsl")):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            text = read(path)
            for spec in INCLUDE_RE.findall(strip_comments(text)):
                where = resolve_include(spec, root, vanilla)
                if where is None:
                    # Vanilla-owned includes are supplied by Minecraft at runtime.
                    # The repository intentionally does not redistribute Mojang's
                    # shader tree, so their existence can only be checked when the
                    # developer has supplied a local Vanilla-stock reference.
                    if spec.startswith("minecraft:") and vanilla is None:
                        continue
                    report.fail("include", rel, "#include <%s> does not resolve" % spec)

    # The replaced fog.glsl must keep every name the vanilla one declares.
    replaced = os.path.join(root, "assets", "minecraft", "shaders", "include", "fog.glsl")
    if vanilla and os.path.isfile(replaced):
        original = read(os.path.join(vanilla, "include", "fog.glsl"))
        mine = read(replaced)
        pattern = re.compile(r"\b(float|vec[234]|mat[234]|void)\s+([A-Za-z_]\w*)\s*\(")
        missing = sorted({m[1] for m in pattern.findall(original)} - {m[1] for m in pattern.findall(mine)})
        if missing:
            report.fail("include", "assets/minecraft/shaders/include/fog.glsl",
                        "no longer declares %s, which other programs call" % ", ".join(missing))


# --------------------------------------------------------------------------
# 4. varyings
# --------------------------------------------------------------------------
def parse_io(text, wanted_stage=None):
    result = {}
    for number, line in enumerate(text.splitlines(), 1):
        match = DECL_RE.match(line)
        if not match:
            continue
        qualifiers, stage, vtype, name = match.groups()
        if wanted_stage is not None and stage != wanted_stage:
            continue
        before = line[:match.start(3)]
        location = LOC_RE.search(before) or LOC_RE.search(line)
        if location is None:
            result.setdefault("__nolayout__", []).append((number, stage, vtype, name))
            continue
        result[int(location.group(1))] = (vtype, "flat" in qualifiers, name, number)
    return result


def find_program_file(root, vanilla, name):
    candidates = [
        os.path.join(root, "assets", "minecraft", "shaders", "core", name),
        os.path.join(root, "assets", "nvs", "shaders", "post", name),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    if vanilla:
        path = os.path.join(vanilla, "core", name)
        if os.path.isfile(path):
            return path
    return None


def check_varyings(root, vanilla, report):
    for fsh in sorted(FRAGMENT_PARTNERS):
        fsh_path = find_program_file(root, vanilla, fsh)
        if fsh_path is None:
            if vanilla is None:
                # Some partner fragments are vanilla-owned and are not copied
                # into this repository. Their pairing is checked when the local
                # vanilla reference tree is supplied.
                continue
            report.fail("varyings", fsh, "fragment program not found")
            continue
        fsh_text = read(fsh_path)
        fsh_io = parse_io(fsh_text, "in")
        rel_fsh = os.path.relpath(fsh_path, root).replace(os.sep, "/")
        if "__nolayout__" in fsh_io:
            for number, stage, vtype, name in fsh_io["__nolayout__"]:
                report.fail("varyings", rel_fsh,
                            "line %d: %s %s %s has no layout(location)"
                            % (number, stage, vtype, name))

        for vsh in FRAGMENT_PARTNERS[fsh]:
            vsh_path = find_program_file(root, vanilla, vsh)
            if vsh_path is None:
                if vanilla is None:
                    continue
                report.fail("varyings", vsh, "vertex program not found")
                continue
            vsh_io = parse_io(read(vsh_path), "out")
            rel_vsh = os.path.relpath(vsh_path, root).replace(os.sep, "/")
            for location, (vtype, flat, name, number) in sorted(fsh_io.items()):
                if location == "__nolayout__":
                    continue
                if location not in vsh_io:
                    report.fail("varyings", rel_fsh,
                                "line %d: input %s at location %d has no output in %s"
                                % (number, name, location, vsh))
                    continue
                out_type, out_flat, out_name, _ = vsh_io[location]
                if out_type != vtype or out_flat != flat:
                    report.fail("varyings", rel_fsh,
                                "line %d: input %s at location %d is %s%s but %s writes %s%s"
                                % (number, name, location, vtype,
                                   " flat" if flat else "", rel_vsh, out_type,
                                   " flat" if out_flat else ""))


# --------------------------------------------------------------------------
# 5. the pack's own symbols
# --------------------------------------------------------------------------
SELF_FUNCTION_RE = re.compile(
    r"^\s*(?:const\s+)?(?:void|float|int|bool|vec[234]|ivec[234]|mat[234]|[A-Za-z_]\w*)\s+(nvs_\w+)\s*\(",
    re.M,
)
MACRO_DEFINE_RE = re.compile(r"^\s*#\s*define\s+(NVS_\w+)", re.M)
MACRO_CONST_RE = re.compile(r"\bconst\s+\w+\s+(NVS_\w+)")
GUARD_LINE_RE = re.compile(r"^\s*#\s*(?:define|ifndef|ifdef)\s+NVS_")


def check_symbols(root, report):
    """Every nvs_ function and NVS_ macro that is used must be defined.

    Both prefixes belong to this pack and nothing in GLSL or in vanilla uses
    them, so a name that is used but never defined is a typo rather than a
    builtin. It is the cheapest way to catch the one class of mistake that a
    compiler would otherwise be the first to find, and it cannot produce a false
    positive.

    The search is pack-wide rather than per-file: it proves the symbol exists,
    not that the file using it includes the file defining it.
    """
    files = []
    for base, _dirs, names in os.walk(os.path.join(root, "assets")):
        for name in sorted(names):
            if name.endswith((".vsh", ".fsh", ".glsl")):
                files.append(os.path.join(base, name))

    defined_functions = set()
    defined_macros = set()
    bodies = {}
    for path in files:
        body = strip_comments(read(path))
        bodies[path] = body
        defined_functions.update(SELF_FUNCTION_RE.findall(body))
        defined_macros.update(MACRO_DEFINE_RE.findall(body))
        defined_macros.update(MACRO_CONST_RE.findall(body))

    for path, body in bodies.items():
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        for name in sorted(set(re.findall(r"\b(nvs_\w+)\s*\(", body))):
            if name not in defined_functions:
                report.fail("symbols", rel, "%s() is called but never defined" % name)
        for number, line in enumerate(body.splitlines(), 1):
            if GUARD_LINE_RE.match(line):
                continue
            for name in sorted(set(re.findall(r"\b(NVS_\w+)\b", line))):
                if name not in defined_macros:
                    report.fail("symbols", rel,
                                "line %d: %s is used but never defined" % (number, name))


# --------------------------------------------------------------------------
# 6. post effects
# --------------------------------------------------------------------------
def check_post_effects(root, report):
    directory = os.path.join(root, "assets")
    for base, _dirs, names in os.walk(directory):
        if os.path.basename(base) != "post_effect":
            continue
        namespace = os.path.basename(os.path.dirname(base))
        for name in sorted(names):
            if not name.endswith(".json"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            try:
                spec = json.loads(read(path))
            except ValueError as error:
                report.fail("post", rel, "not valid JSON: %s" % error)
                continue

            targets = spec.get("targets", {})
            passes = spec.get("passes", [])
            if not passes:
                report.fail("post", rel, "no passes")
            for target in targets:
                if target.startswith("minecraft:"):
                    report.fail("post", rel,
                                "a post effect may only use minecraft:main; %r is refused" % target)

            for index, single in enumerate(passes):
                where = "%s pass %d" % (rel, index)
                for key in ("vertex_shader", "fragment_shader", "output"):
                    if key not in single:
                        report.fail("post", where, "missing %r" % key)

                output = single.get("output")
                if output != "minecraft:main" and output not in targets:
                    report.fail("post", where, "output %r is not a declared target" % output)

                inputs = single.get("inputs", [])
                samplers = []
                for entry in inputs:
                    target = entry.get("target")
                    if target != "minecraft:main" and target not in targets:
                        report.fail("post", where, "input target %r is not declared" % target)
                    sampler_name = entry.get("sampler_name")
                    if not sampler_name:
                        report.fail("post", where, "input without sampler_name")
                        continue
                    if sampler_name in samplers:
                        report.fail("post", where, "two inputs share sampler_name %r" % sampler_name)
                    samplers.append(sampler_name)

                for key in ("vertex_shader", "fragment_shader"):
                    identifier = single.get(key)
                    if not identifier:
                        continue
                    found = find_post_program(root, identifier)
                    if found is None:
                        report.fail("post", where, "%s %r not found" % (key, identifier))
                        continue
                    check_post_program_scope(root, found, samplers, single.get("uniforms", {}), report)

    # The end-of-frame hook is the whole point of the pack's post-processing.
    hook = os.path.join(root, "assets", "minecraft", "post_effect", "end_of_frame.json")
    if not os.path.isfile(hook):
        report.fail("post", "assets/minecraft/post_effect/end_of_frame.json",
                    "without this file the pack runs no post effect at all")


def find_post_program(root, identifier):
    if ":" in identifier:
        namespace, path = identifier.split(":", 1)
    else:
        namespace, path = "minecraft", identifier
    directory = os.path.join(root, "assets", namespace, "shaders")
    if not os.path.isdir(directory):
        return None
    for base, _dirs, names in os.walk(directory):
        for name in names:
            stem = name.rsplit(".", 1)[0]
            rel = os.path.relpath(os.path.join(base, stem), os.path.join(root, "assets", namespace, "shaders"))
            if rel.replace(os.sep, "/") == path:
                return os.path.join(base, name)
    return None


def check_post_program_scope(root, path, samplers, declared_uniforms, report):
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    text = read(path)
    lines = text.splitlines()

    allowed_samplers = {name + "Sampler" for name in samplers}
    for number, line in enumerate(lines, 1):
        sampler = SAMPLER_RE.match(line)
        if sampler and sampler.group(1) not in allowed_samplers:
            report.fail("post", rel,
                        "line %d: sampler %r is not one of this pass's inputs (%s)"
                        % (number, sampler.group(1), ", ".join(sorted(allowed_samplers)) or "none"))
        block = BLOCK_RE.match(line)
        if block:
            name = block.group(1)
            if name not in POST_ALLOWED_BLOCKS and name not in declared_uniforms:
                report.fail("post", rel,
                            "line %d: uniform block %r is neither a post-provided block nor "
                            "listed in the JSON \"uniforms\"" % (number, name))


# --------------------------------------------------------------------------
def main(argv):
    root = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    report = Report()
    vanilla = find_vanilla(root)

    if vanilla is None:
        report.note("no 'Vanilla-stock ' folder found: include and partner checks are weaker")
    else:
        report.note("vanilla reference: %s" % os.path.relpath(vanilla, root))

    check_structure(root, report)
    check_includes(root, vanilla, report)
    check_varyings(root, vanilla, report)
    check_symbols(root, report)
    check_post_effects(root, report)

    for base, _dirs, names in os.walk(os.path.join(root, "assets")):
        for name in sorted(names):
            if not name.endswith((".vsh", ".fsh", ".glsl")):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            text = read(path)
            is_include = os.path.basename(base) == "include"
            check_glsl_hygiene(root, rel, text, report, is_include)
            if not is_include:
                check_declarations(name, text, report, rel)

    print("Native Vanilla Shaders - static checks")
    print("=" * 60)
    for note in report.notes:
        print("note: %s" % note)
    if not report.errors:
        print("PASS: every static check passed")
        print("This is not a compile: GLSL validity still needs the game.")
        return 0

    print("FAIL: %d problem(s)" % len(report.errors))
    for check, where, message in report.errors:
        print("  [%s] %s\n      %s" % (check, where, message))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
