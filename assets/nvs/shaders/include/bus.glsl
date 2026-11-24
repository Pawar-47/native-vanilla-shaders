#ifndef NVS_BUS_GLSL
#define NVS_BUS_GLSL

// NVS screen data bus, adapted from carlodrift's CC0 data-bus example.
// Column x=0 is reserved for core-shader -> post-effect data. Every world
// fragment program must protect this column before the bus can be enabled.
// Rows are counted from the bottom of the framebuffer.
#define NVS_BUS_ROW_MARKER 0
#define NVS_BUS_ROW_PROJ 1
#define NVS_BUS_ROW_VIEW 17
// The sky view matrix is a pure rotation, so only its 3x3 basis is carried.
#define NVS_BUS_ROW_SKY 26
#define NVS_BUS_ROW_FOG 27
#define NVS_BUS_ROW_FOG_PARAMS 28
#define NVS_BUS_ROW_SUN 34
#define NVS_BUS_SUN_ROWS 4
#define NVS_BUS_SKY_ROWS 38

// The bus is valid only in perspective world rendering. Orthographic GUI and
// item-atlas passes must not discard their first column.
#define NVS_BUS_PROTECT if (gl_FragCoord.x < 1.0 && ProjMat[2][3] != 0.0) { discard; }
#define NVS_BUS_PROTECT_ALWAYS if (gl_FragCoord.x < 1.0) { discard; }

// Exact 32-bit float transport for unblended sky-writer fragments.
vec4 nvs_bus_packFloat(float value) {
    uint bits = floatBitsToUint(value);
    return vec4(float((bits >> 24u) & 255u),
                float((bits >> 16u) & 255u),
                float((bits >> 8u) & 255u),
                float(bits & 255u)) / 255.0;
}

float nvs_bus_unpackFloat(vec4 value) {
    uvec4 bytes = uvec4(round(value * 255.0));
    uint bits = (bytes.x << 24u) | (bytes.y << 16u) | (bytes.z << 8u) | bytes.w;
    return uintBitsToFloat(bits);
}

// Signed [-1,1] values encoded in RGB; alpha remains 1 for additive blending.
vec4 nvs_bus_packSigned(float value) {
    uint q = uint(round(clamp(value * 0.5 + 0.5, 0.0, 1.0) * 16777215.0));
    return vec4(float((q >> 16u) & 255u),
                float((q >> 8u) & 255u),
                float(q & 255u), 255.0) / 255.0;
}

float nvs_bus_unpackSigned(vec4 value) {
    uvec3 bytes = uvec3(round(value.rgb * 255.0));
    uint q = (bytes.x << 16u) | (bytes.y << 8u) | bytes.z;
    return float(q) / 16777215.0 * 2.0 - 1.0;
}

// Clip-space corner of the reserved strip covering [firstRow, firstRow+rows).
vec4 nvs_busStripCorner(vec2 corner, int firstRow, int rows, vec2 screenSize) {
    vec2 pixel = vec2(corner.x, float(firstRow) + corner.y * float(rows));
    return vec4(-1.0 + 2.0 * pixel / screenSize, 0.0, 1.0);
}

#endif
