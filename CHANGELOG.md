# Changelog

All notable changes to this pack. The pack version is independent of the Minecraft version.

## Phase 1 complete — 2026-11-24

### Added and expanded

**Sky, atmosphere and celestial**
- Reconstructed the sky in a post pass using the game's sky/fog colours and world direction.
- Added distance-aware aerial perspective and a soft loaded-world edge fade, matching the core shader's smoothstep fog curve and fog alpha.
- Added a 38-row screen data bus carrying projection, the 3×3 view rotation, sky/fog values, fog distances, sun direction and rain brightness.
- Preserved the moon, stars and vanilla sunrise glow over the reconstructed sky; shared a rain-aware solar disc, corona and aureole between sky and water reflections.
- Replaced the full per-fragment 4×4 projection inverse with analytic perspective unprojection; opaque atmosphere pixels skip the four sun-data bus fetches.

**Water**
- Added water surface markers, top/side classification and quantized side-face orientation.
- Added screen-space reflections with a 24-step ray budget and four refinement steps, edge fading and procedural sky/cloud/sun fallback.
- Added wave-driven refraction, Fresnel, distance fog, absorption and post-pass whitecaps.
- Added an eight-direction gravity-dispersed wave spectrum, stable spatial domain warping, screen-footprint filtering and seamless day-wrap animation; wave slope and foam share the same filtered height field.
- Reduced reflected-cloud noise octaves for the integrated-GPU target and limited the water pass's expensive bus decode to tagged water pixels.

**Clouds, lighting and post**
- Added 3D vertical density breakup to the native cloud shell while retaining the shared 2D mass field for shadows/reflections; empty fragments are rejected before the extra 3D noise sampling.
- Retained cloud-shadow, lightmap, plant-sway, bloom, grading, sharpen, vignette and optional FXAA work.
- Added tunable controls for SSR steps/growth, reflection/refraction distortion, reflected-cloud detail and atmosphere haze.

**Documentation**
- Updated architecture, feature matrix, limitations, runtime test plan and README to reflect the data bus, atmosphere and water post pipeline.
- Documented the remaining OIT water-marker risk and other native-pipeline limitations.

### Verification status

Phase 1 remains in development. The current GitHub Actions pipeline passes static checks, glslang syntax/type compilation for the supported shader variants, manifest generation, installable-pack creation, archive-root verification and artifact upload. The recent eight-wave water spectrum and shallow 3D cloud-density changes are compiled and packaged, but still need the remaining source review before the pack is handed over for Phase 2.

The glslang pass is not Minecraft ShaderC, and no in-game rendering or performance result is claimed. Known native-pipeline limitations are recorded in [LIMITATIONS.md](LIMITATIONS.md).


## Beta 1 — 2026-11-24

- Replaced repeated circular cloud puffs with asymmetric, warped multi-scale cloud banks and separated coverage.
- Added three independently seeded cloud layers at different heights and scales, including distant high and horizon formations.
- Added finite-difference cloud normals for soft crown lighting, shaded folds and more convincing volume.
- Neutralised most per-channel lightmap tint on particles while preserving particle texture and vertex colours, reducing coloured rain/particle speckles.
- Removed final ordered dither and reduced bloom, saturation and sharpening to avoid coloured crawling around thin moving weather streaks.
- Changed release automation to publish one fixed Beta 1 release only for the Beta 1 merge; ordinary commits no longer create a new release each time.
- CI regenerates manifests before checking them on pull requests, then refreshes the committed hashes on main.


### Beta 1 water and colour refinement — 2026-11-24

- Changed the water spectrum to a single prevailing wind direction with layered wavelengths, so wave trains travel coherently instead of crossing from several directions.
- Increased water-column absorption and the deep teal depth veil to suppress luminous, rectangular vanilla seabed patterns while retaining restrained shallow-water detail.
- Added a reflection-sample cleanup filter for isolated high-chroma highlights, targeting thin coloured rain-particle streaks mirrored across the water.
- Refined the global grade with brighter exposure, stronger midtone contrast, richer saturation, a gentler highlight shoulder and subtle cool-shadow / warm-highlight film toning.
- Preserved the existing cloud design and low-end-oriented shader budgets.
