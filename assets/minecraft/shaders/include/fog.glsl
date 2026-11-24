#ifndef MINECRAFT_FOG_GLSL
#define MINECRAFT_FOG_GLSL

#include <nvs:config.glsl>

layout(std140) uniform Fog {
    vec4 FogColor;
    float FogEnvironmentalStart;
    float FogEnvironmentalEnd;
    float FogRenderDistanceStart;
    float FogRenderDistanceEnd;
    float FogSkyEnd;
    float FogCloudsEnd;
};

float linear_fog_value(float vertexDistance, float fogStart, float fogEnd) {
    if (vertexDistance <= fogStart) {
        return 0.0;
    } else if (vertexDistance >= fogEnd) {
        return 1.0;
    }

    return (vertexDistance - fogStart) / (fogEnd - fogStart);
}

float total_fog_value(float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmantalEnd, float renderDistanceStart, float renderDistanceEnd) {
    return max(linear_fog_value(sphericalVertexDistance, environmentalStart, environmantalEnd), linear_fog_value(cylindricalVertexDistance, renderDistanceStart, renderDistanceEnd));
}

// Replaced vanilla include. Every block and function here keeps its vanilla name
// and signature: other programs call them, and a mistake in an include breaks
// every program that uses it.
//
// The one change is the curve. Vanilla's fog is linear in distance, which shows
// as a visible line where the fog starts and a wall where it ends. A smoothstep
// keeps both ends exactly where the game put them (0 at the start, 1 at the
// end) and spreads the transition over the whole span, so there is no start line
// and no wall. FogColor and its alpha are untouched, so underwater fog,
// blindness, the darkness effect and rain fog all keep the colours and distances
// the game chose.
vec4 apply_fog(vec4 inColor, float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmantalEnd, float renderDistanceStart, float renderDistanceEnd, vec4 fogColor) {
    float fogValue = total_fog_value(sphericalVertexDistance, cylindricalVertexDistance, environmentalStart, environmantalEnd, renderDistanceStart, renderDistanceEnd);
    fogValue = fogValue * fogValue * (3.0 - 2.0 * fogValue);
    return vec4(mix(inColor.rgb, fogColor.rgb, fogValue * fogColor.a), inColor.a);
}

float fog_spherical_distance(vec3 pos) {
    return length(pos);
}

float fog_cylindrical_distance(vec3 pos) {
    float distXZ = length(pos.xz);
    float distY = abs(pos.y);
    return max(distXZ, distY);
}

#endif
