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
//
// TODO(pcwalton): Generate a Z-buffer.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#include "fill.inc.glsl"

layout(local_size_x = 256) in;

layout(std430, binding = 0) buffer bMetadata {
    restrict readonly uvec4 iMetadata[];
};

layout(std430, binding = 1) buffer bBackdrops {
    restrict readonly int iBackdrops[];
};

layout(std430, binding = 2) buffer bAlphaTiles {
    restrict uint iAlphaTiles[];
};

void main() {
    uint metadataOffset = gl_WorkGroupID.y;
    uint tileX = uint(gl_LocalInvocationID.x);

    uvec4 metadata = iMetadata[metadataOffset];
    uvec2 tileSize = metadata.xy;
    uint tileBufferOffset = metadata.z, backdropOffset = metadata.w;

    if (tileX >= tileSize.x)
        return;

    int backdrop = iBackdrops[backdropOffset + tileX];
    for (uint tileY = 0; tileY < tileSize.y; tileY++) {
        uint index = (tileBufferOffset + tileY * tileSize.x + tileX) * 3 + 2;
        uint tileWord = iAlphaTiles[index];
        int delta = (int(tileWord) << 8) >> 24;
        iAlphaTiles[index] = (tileWord & 0xff00ffff) | ((uint(backdrop) & 0xff) << 16);
        backdrop += delta;
    }
}
