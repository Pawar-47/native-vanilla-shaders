# Installing Native Vanilla Shaders

## You need

- **Minecraft Java Edition 26.3** (the version matters; see below).
- **Nothing else.** No Iris, no OptiFine, no Oculus, no Sodium, no mod loader.
- Graphics settings that give the shaders their geometry:
  - **Graphics: Fancy** — the clouds need their volume, and the water needs the
    translucent terrain pass.
  - **Clouds: Fancy** — the pack works with Fast clouds, but they are a single
    flat layer, so the volume shading has nothing to shade.
  - **Improved Transparency: off** for the intended water effects. The native
    OIT branches remain intact, but water markers are only written in the
    non-OIT colour pass, so screen-space reflections/refraction are not reliable
    with Improved Transparency enabled.

## What to copy, and what not to

The pack itself is **`pack.mcmeta` plus `assets/`**. That is all Minecraft reads.

The repository also contains the user-supplied vanilla reference under
`reference/vanilla-stock/` and the development tools/docs. The external visual
benchmark and local research notes are not bundled. **Do not copy the repository
root into `resourcepacks/`.** The game would ignore those paths; use the clean
package produced by the script below.

Build a clean pack folder, and optionally a proper `.zip`, with:

```sh
python3 tools/package.py --zip
```

That writes `dist/Native Vanilla Shaders/` and
`dist/Native Vanilla Shaders 1.0.0 - MC 26.3.zip`, containing only the pack. If you
would rather not run anything, copy `pack.mcmeta` and `assets/` into a folder
called `Native Vanilla Shaders` yourself, plus the `.md` files if you want the
documentation along for the ride.

## Install

1. Open the Minecraft game directory:
   - Windows: `%appdata%\.minecraft`
   - macOS: `~/Library/Application Support/minecraft`
   - Linux: `~/.minecraft`
2. Put the pack — either the folder `Native Vanilla Shaders` or the `.zip` — into
   `resourcepacks/`.
   For the folder form, `pack.mcmeta` must be directly inside it:
   `resourcepacks/Native Vanilla Shaders/pack.mcmeta`. Not nested twice.
   For the `.zip`, `pack.mcmeta` must be at the archive root, not inside a folder
   in the archive; `tools/package.py --zip` gets this right.
3. In game: **Options → Resource Packs**, select the pack, move it to Selected,
   **Done**.
4. If Minecraft shows the pack as incompatible, the game version is not 26.3. The
   pack declares `min_format` and `max_format` `97`, which is 26.3's resource
   format.

If the pack's icon area shows it as broken, the game disabled it during a reload:
check `logs/latest.log` for `Caught error loading resourcepacks, removing all
selected resourcepacks`. That message means a shader failed to compile, and the
game responded by dropping *every* selected pack. See [TESTING.md](TESTING.md).

## Uninstall

Deselect the pack, or delete the folder. Nothing is written outside it.

## Switches, since there is no options menu

26.3 has no shader options screen for resource packs, so the pack has two
mechanisms, both documented and both reversible by hand.

### 1. Tunables

Edit [`assets/nvs/shaders/include/config.glsl`](assets/nvs/shaders/include/config.glsl).
Every value is guarded with `#ifndef`, so setting one is a one-line edit and no
value can break the shaders' interfaces. The useful ones:

| Define | Default | Effect |
|---|---|---|
| `NVS_POST_BLOOM` | `0.55` | Bloom strength. `0.0` disables it. |
| `NVS_POST_SHARPEN` | `0.18` | Sharpen. `0.0` disables it. |
| `NVS_POST_VIGNETTE` | `0.10` | Vignette. `0.0` disables it. |
| `NVS_CLOUD_OCTAVES` | `4` | Cloud detail. `3` is the cheapest useful value. |
| `NVS_CLOUD_CUTOFF` | `0.30` | Higher gives thinner, wispier clouds. |
| `NVS_WATER_WAVE_STRENGTH` | `0.60` | Eight-wave surface slope. `0.0` is a mirror. |
| `NVS_WATER_SSR_STEPS` | `24` | Screen-space reflection ray steps. Lower to `16` for performance. |
| `NVS_WATER_SSR_REFINE_STEPS` | `4` | Reflection hit refinement steps. Lower to `3` for performance. |
| `NVS_CLOUD_VOLUME_OCTAVES` | `2` | Vertical cloud-shell detail. `1` is cheaper. |
| `NVS_PLANT_SWAY` | `0.055` | Plant sway. `0.0` makes plants still. |
| `NVS_NIGHT_STRENGTH` | `1.0` | Nebula and star field. `0.0` removes them. |
| `NVS_CLOUD_SHADOW_STRENGTH` | `0.18` | Cloud shadows on the ground. `0.0` disables them. |
| `NVS_SKYLIGHT_CURVE` | `1.15` | Higher darkens caves further. `1.0` is vanilla's falloff. |

A shader change is picked up by pressing **F3 + T** (reload resource packs). If
you edit a shader while the game is running and something goes wrong, F3+T will
report it in the log.

### 2. Whole features

- **Do not remove the default end-of-frame effect for normal performance
  tuning.** It is required for the data-bus sky/fog reconstruction and above-water
  water reflections/refraction, as well as bloom and the final grade. Removing
  `assets/minecraft/post_effect/end_of_frame.json` is a last-resort compatibility
  fallback only; it also removes those sky/water features, not just post polish.
- **Antialiasing on**: it is not in the default chain, because it costs a
  full-resolution pass and softens the block edges. Apply it as its own effect:

  ```
  /posteffect add @s nvs:fxaa
  /posteffect remove @s nvs:fxaa
  ```

  `/posteffect` needs permission level 2, so it needs cheats enabled or a
  server operator. It is per-player and lasts until you remove it or rejoin.

## Performance, briefly

The pack is tuned for an integrated GPU. If it is too slow, reduce cost without
disabling the sky and water pipeline:

1. `NVS_WATER_SSR_STEPS 16` and `NVS_WATER_SSR_REFINE_STEPS 3`.
2. `NVS_CLOUD_OCTAVES 3`, `NVS_CLOUD_VOLUME_OCTAVES 1` and
   `NVS_CLOUD_CUTOFF 0.38`.
3. `NVS_CLOUD_SHADOW_OCTAVES 2` and `NVS_CLOUD_SHADOW_DETAIL_OCTAVES 1`.
4. `NVS_NIGHT_STRENGTH 0.0` and `NVS_NEBULA_OCTAVES 2`.
5. `NVS_WATER_RIPPLE 0.015` and `NVS_WATER_FOAM 0.0`.
6. Set **Clouds: Fast** only if necessary — the pack then shades a flat layer
   instead of a volume.

Removing `end_of_frame.json` is not a routine performance setting; it disables
the reconstructed sky/fog and above-water water effects too.
