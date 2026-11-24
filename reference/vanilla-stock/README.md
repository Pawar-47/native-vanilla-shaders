# Vanilla Stock Reference

This directory is reserved for the unmodified Minecraft Java Edition 26.3 vanilla shader resources.

## Upload instructions

1. Extract the supplied vanilla stock archive.
2. Upload the extracted files and folders into this directory.
3. Preserve the archive's original directory hierarchy, filenames, and file contents. Do not rename, flatten, or edit the vanilla files.
4. Keep the original vanilla assets separate from the shader-pack implementation under `assets/nvs/`.
5. Include all relevant shader source and support files, including `.vsh`, `.fsh`, `.glsl`, JSON, and related resources.

The expected layout may resemble:

```
reference/
└── vanilla-stock/
    ├── README.md
    └── assets/
        └── minecraft/
            └── shaders/
                ├── core/
                ├── post/
                └── ...
```

The exact layout in the archive takes precedence over this illustrative example.

## Provenance

- Intended reference version: Minecraft Java Edition 26.3
- Purpose: read-only baseline for comparing native shader interfaces, uniforms, includes, render stages, and vanilla behavior.
- Keep this reference unmodified. Record the exact game build and archive provenance here if they are available.

**Important:** This is reference material, not an active shader-pack namespace. Do not point the pack manifest or runtime at this directory.
