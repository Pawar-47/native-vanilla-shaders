# Changelog

All notable changes to this pack. The pack version is independent of the Minecraft version.

## Unreleased — Phase 1 development

### Added and expanded

**Sky, atmosphere and celestial**
- Reconstructed the sky in a post pass using the game's sky/fog colours and world direction.
- Added distance-aware aerial perspective and a soft loaded-world edge fade, matching the core shader's smoothstep fog curve and fog alpha.
- Added a 38-row screen data bus carrying projection, the 3×3 view rotation, sky/fog values, fog distances, sun direction and rain brightness.
- Preserved the moon, stars and vanilla sunrise glow over the reconstructed sky; added the solar disc/corona to the reflected sky path.

**Water**
- Added water surface markers, top/side classification and quantized side-face orientation.
- Added screen-space reflections with a 24-step ray budget and four refinement steps, edge fading and procedural sky/cloud/sun fallback.
- Added wave-driven refraction, Fresnel, distance fog, absorption and post-pass whitecaps.
- Added an eight-direction gravity-dispersed wave spectrum, stable spatial domain warping, screen-footprint filtering and seamless day-wrap animation.
- Reduced reflected-cloud noise octaves for the integrated-GPU target and limited the water pass's expensive bus decode to tagged water pixels.

**Clouds, lighting and post**
- Added 3D vertical density breakup to the native cloud shell while retaining the shared 2D mass field for water reflections.
- Retained cloud-shadow, lightmap, plant-sway, bloom, grading, sharpen, vignette and optional FXAA work.
- Added tunable controls for SSR steps/growth, reflection/refraction distortion, reflected-cloud detail and atmosphere haze.

**Documentation**
- Updated architecture, feature matrix, limitations, runtime test plan and README to reflect the data bus, atmosphere and water post pipeline.
- Documented the remaining OIT water-marker risk and other native-pipeline limitations.

### Verification status

Phase 1 remains in development. The current GitHub Actions pipeline passes static checks, glslang syntax/type compilation for the supported shader variants, manifest generation, installable-pack creation, archive-root verification and artifact upload. The recent eight-wave water spectrum and shallow 3D cloud-density changes are compiled and packaged, but still need the remaining source review before the pack is handed over for Phase 2.

The glslang pass is not Minecraft ShaderC, and no in-game rendering or performance result is claimed. Known native-pipeline limitations are recorded in [LIMITATIONS.md](LIMITATIONS.md).
