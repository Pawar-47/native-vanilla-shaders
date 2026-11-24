#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>

layout(location = 4) in float nvsBusRow;

layout(location = 0) out vec4 fragColor;

void main() {
    int row = int(floor(nvsBusRow));
    if (row == NVS_BUS_ROW_MARKER) {
        fragColor = vec4(1.0, 0.0, 1.0, 1.0);
    } else if (row >= NVS_BUS_ROW_PROJ && row < NVS_BUS_ROW_VIEW) {
        int k = row - NVS_BUS_ROW_PROJ;
        fragColor = nvs_bus_packFloat(ProjMat[k / 4][k % 4]);
    } else if (row >= NVS_BUS_ROW_VIEW && row < NVS_BUS_ROW_SKY) {
        int k = row - NVS_BUS_ROW_VIEW;
        fragColor = nvs_bus_packFloat(ModelViewMat[k / 3][k % 3]);
    } else if (row == NVS_BUS_ROW_SKY) {
        fragColor = vec4(ColorModulator.rgb, 1.0);
    } else if (row == NVS_BUS_ROW_FOG) {
        fragColor = FogColor;
    } else if (row >= NVS_BUS_ROW_FOG_PARAMS && row < NVS_BUS_ROW_SUN) {
        int k = row - NVS_BUS_ROW_FOG_PARAMS;
        float fogValues[6] = float[6](
            FogEnvironmentalStart, FogEnvironmentalEnd,
            FogRenderDistanceStart, FogRenderDistanceEnd,
            FogSkyEnd, FogCloudsEnd
        );
        fragColor = nvs_bus_packFloat(fogValues[k]);
    } else {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
}
