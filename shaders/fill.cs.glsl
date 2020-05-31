#version 430

// pathfinder/shaders/fill.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#include "fill_area.inc.glsl"

layout(local_size_x = 16, local_size_y = 4) in;

//uniform writeonly image2D uDest;
uniform ivec2 uFramebufferSize;
uniform sampler2D uAreaLUT;
uniform ivec2 uTileRange;
uniform int uBinnedOnGPU;

layout(std430, binding = 0) buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1) buffer bFillTileMap {
    restrict readonly int iFillTileMap[];
};

layout(std430, binding = 2) buffer bTiles {
    // [0]: tile coords, 16-bit packed x/y
    // [1]: alpha tile ID
    // [2]: path ID
    // [3]: color/ctrl/backdrop word
    restrict readonly int iTiles[];
};

layout(std430, binding = 3) buffer bDestBufferMetadata {
    restrict uint iDestBufferMetadata[];
};

layout(std430, binding = 4) buffer bDestBuffer {
    restrict uint iDestBuffer[];
};

layout(std430, binding = 5) buffer bDestBufferTail {
    restrict uvec4 iDestBufferTail[];
};

void main() {
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID.xy) * ivec2(1, 4);

    // This is a workaround for the 64K workgroup dispatch limit in OpenGL.
    uint tileIndexOffset = gl_WorkGroupID.x | (gl_WorkGroupID.y << 16);
    uint tileIndex = tileIndexOffset + uint(uTileRange.x);
    if (tileIndex >= uTileRange.y)
        return;

    int fillIndex = iFillTileMap[tileIndex];
    if (fillIndex < 0)
        return;

    vec4 coverages = vec4(0.0);
    int iteration = 0;
    do {
        uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
        vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                fillTo   & 0xffff, fillTo   >> 16) / 256.0;

        coverages += computeCoverage(lineSegment.xy - (vec2(tileSubCoord) + vec2(0.5)),
                                     lineSegment.zw - (vec2(tileSubCoord) + vec2(0.5)),
                                     uAreaLUT);

        fillIndex = int(iFills[fillIndex * 3 + 2]);
        iteration++;
    } while (fillIndex >= 0 && iteration < 1024);

    // TODO(pcwalton): Take backdrop into account!
    if (all(equal(coverages, vec4(0.0))))
        return;

    // If we binned on GPU, then `tileIndex` refers to a *global* tile index, and we have to
    // convert that to an alpha tile index. If we binned on CPU, though, `tileIndex` is an alpha
    // tile index.
    //
    // This is unfortunately very confusing, but I don't know of any other way to make the D3D10
    // rasterization pipeline work simultaneously with compute.
    uint alphaTileIndex;
    if (uBinnedOnGPU != 0)
        alphaTileIndex = iTiles[tileIndex * 4 + 1];
    else
        alphaTileIndex = tileIndex;

    int packedTileCoord = int(iTiles[tileIndex * 4 + 0]);
    ivec2 tileCoord = ivec2((packedTileCoord << 16) >> 16, packedTileCoord >> 16);
    ivec2 pixelCoord = tileCoord * ivec2(16, 4) + ivec2(gl_LocalInvocationID.xy);
    uint destBufferOffset = pixelCoord.x + pixelCoord.y * uFramebufferSize.x;

    uvec4 scaledCoverages = uvec4(round(min(abs(coverages), vec4(1.0)) * vec4(255.0)));
    uint packedCoverages = scaledCoverages.x |
                           (scaledCoverages.y << 8) |
                           (scaledCoverages.z << 16) |
                           (scaledCoverages.w << 24);

    uint tailOffset = atomicAdd(iDestBufferMetadata[0], 1);
    iDestBufferTail[tailOffset].x = packedCoverages;
    iDestBufferTail[tailOffset].y = iTiles[tileIndex * 4 + 2];
    iDestBufferTail[tailOffset].z = iTiles[tileIndex * 4 + 3];
    iDestBufferTail[tailOffset].w = atomicExchange(iDestBuffer[destBufferOffset], tailOffset);
}
