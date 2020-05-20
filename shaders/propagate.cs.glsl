#version 430

// pathfinder/shaders/propagate.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

// Sum up backdrops to propagate fills across tiles.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#include "fill.inc.glsl"

// TODO(pcwalton): Improve occupancy!
layout(local_size_x = 256) in;

uniform ivec2 uFramebufferTileSize;

layout(std430, binding = 0) buffer bMetadata {
    restrict readonly uvec4 iMetadata[];
};

layout(std430, binding = 1) buffer bBackdrops {
    restrict readonly int iBackdrops[];
};

layout(std430, binding = 2) buffer bAlphaTiles {
    restrict uint iAlphaTiles[];
};

layout(std430, binding = 3) buffer bZBuffer {
    restrict int iZBuffer[];
};

void main() {
    uint pathIndex = gl_WorkGroupID.y;
    uint tileX = uint(gl_LocalInvocationID.x);

    uvec4 tileRect = iMetadata[pathIndex * 2 + 0];
    uvec4 offsets = iMetadata[pathIndex * 2 + 1];
    uvec2 tileSize = tileRect.zw - tileRect.xy;
    uint tileBufferOffset = offsets.x, backdropOffset = offsets.y;
    bool zWrite = offsets.z != 0;

    if (tileX >= tileSize.x)
        return;

    int backdrop = iBackdrops[backdropOffset + tileX];
    for (uint tileY = 0; tileY < tileSize.y; tileY++) {
        uint index = (tileBufferOffset + tileY * tileSize.x + tileX) * 4;
        uint tileWord = iAlphaTiles[index + 3];
        int delta = (int(tileWord) << 8) >> 24;
        iAlphaTiles[index + 3] = (tileWord & 0xff00ffff) | ((uint(backdrop) & 0xff) << 16);

        // Write to Z-buffer if necessary.
        if (zWrite && backdrop != 0 && (iAlphaTiles[index + 1] & 0x80000000) != 0) {
            ivec2 tileCoord = ivec2(tileX, tileY) + ivec2(tileRect.xy);
            int zBufferIndex = tileCoord.y * uFramebufferTileSize.x + tileCoord.x;
            atomicMax(iZBuffer[zBufferIndex], int(pathIndex));
        }

        backdrop += delta;
    }
}
