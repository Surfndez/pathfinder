#version 430

// pathfinder/shaders/tile_fill.cs.glsl
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

layout(local_size_x = 16, local_size_y = 4) in;

uniform writeonly image2D uDest;
uniform sampler2D uAreaLUT;
uniform ivec2 uFramebufferTileSize;
uniform sampler2D uTextureMetadata;
uniform ivec2 uTextureMetadataSize;

#include "fill_area.inc.glsl"

layout(std430, binding = 0) buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1) buffer bTileLinkMap {
    restrict readonly ivec2 iTileLinkMap[];
};

layout(std430, binding = 2) buffer bTiles {
    restrict readonly int iTiles[];
};

layout(std430, binding = 3) buffer bInitialTileMap {
    restrict readonly uint iInitialTileMap[];
};
/*

bool initFill(inout int tileIndex, inout int fillIndex, uint tileIndexOffset) {
    tileIndex = int(iInitialTileMap[tileIndexOffset]);
    while (tileIndex >= 0) {
        fillIndex = iTileLinkMap[tileIndex].x;
        if (fillIndex >= 0)
            return true;
        tileIndex = iTileLinkMap[tileIndex].y;
    }
    return false;
}

bool nextFill(inout int tileIndex, inout int fillIndex) {
    fillIndex = int(iFills[fillIndex * 3 + 2]);
    if (fillIndex >= 0)
        return true;
    tileIndex = iTileLinkMap[tileIndex].y;

    while (tileIndex >= 0) {
        fillIndex = iTileLinkMap[tileIndex].x;
        if (fillIndex >= 0)
            return true;
        tileIndex = iTileLinkMap[tileIndex].y;
    }
    return false;
}
*/

void main() {
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID.xy) * ivec2(1, 4);
    ivec2 tileCoord = ivec2(gl_WorkGroupID.xy);

    vec4 colors[4] = {vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)};
    uint tileIndexOffset = tileCoord.x + tileCoord.y * uFramebufferTileSize.x;
    int tileIndex = int(iInitialTileMap[tileIndexOffset]);
    uint iteration = 0;

    while (tileIndex >= 0) {
        uint pathIndex = uint(iTiles[tileIndex * 4 + 2]);
        uint colorIndex = uint(iTiles[tileIndex * 4 + 3]) & 0xffff;
        int backdrop = iTiles[tileIndex * 4 + 3] >> 24;

        vec4 coverages = vec4(backdrop);
        int fillIndex = iTileLinkMap[tileIndex].x;
        while (fillIndex >= 0) {
            uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
            vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                    fillTo   & 0xffff, fillTo   >> 16) / 256.0;

            coverages += computeCoverage(lineSegment.xy - (vec2(tileSubCoord) + vec2(0.5)),
                                         lineSegment.zw - (vec2(tileSubCoord) + vec2(0.5)),
                                         uAreaLUT);

            fillIndex = int(iFills[fillIndex * 3 + 2]);

            iteration++;
            if (iteration >= 16384)
                return;
        }

        vec2 textureMetadataScale = vec2(1.0) / vec2(uTextureMetadataSize);
        vec2 metadataEntryCoord = vec2(colorIndex % 128 * 4, colorIndex / 128);
        vec2 colorTexMatrix0Coord = (metadataEntryCoord + vec2(0.5, 0.5)) * textureMetadataScale;
        vec2 colorTexOffsetsCoord = (metadataEntryCoord + vec2(1.5, 0.5)) * textureMetadataScale;
        vec2 baseColorCoord = (metadataEntryCoord + vec2(2.5, 0.5)) * textureMetadataScale;
        vec4 colorTexMatrix0 = texture(uTextureMetadata, colorTexMatrix0Coord);
        vec4 colorTexOffsets = texture(uTextureMetadata, colorTexOffsetsCoord);
        vec4 baseColor = texture(uTextureMetadata, baseColorCoord);

        for (uint y = 0; y < 4; y++) {
            vec4 thisColor = vec4(baseColor.rgb, baseColor.a * clamp(abs(coverages[y]), 0.0, 1.0));
            colors[y] = mix(colors[y], thisColor, thisColor.a);
        }

        tileIndex = iTileLinkMap[tileIndex].y;
    }

    ivec2 destCoord = tileCoord * ivec2(16) + tileSubCoord;
    for (uint y = 0; y < 4; y++)
        imageStore(uDest, destCoord + ivec2(0, y), colors[y]);
}
