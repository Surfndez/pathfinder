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

void main() {
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID.xy) * ivec2(1, 4);
    ivec2 tileCoord = ivec2(gl_WorkGroupID.xy);

    uint tileIndexOffset = tileCoord.x + tileCoord.y * uFramebufferTileSize.x;
    int tileIndex = -1, fillIndex = -1;
    vec4 coverages = vec4(0.0);

    if (initFill(tileIndex, fillIndex, tileIndexOffset)) {
        int iteration = 0;
        do {
            uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
            vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                    fillTo   & 0xffff, fillTo   >> 16) / 256.0;

            coverages += computeCoverage(lineSegment.xy - (vec2(tileSubCoord) + vec2(0.5)),
                                        lineSegment.zw - (vec2(tileSubCoord) + vec2(0.5)),
                                        uAreaLUT);

            iteration++;
        } while (iteration < 1024 && nextFill(tileIndex, fillIndex));
    }

    ivec2 destCoord = tileCoord * ivec2(16) + tileSubCoord;
    imageStore(uDest, destCoord + ivec2(0, 0), vec4(coverages.xxx, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 1), vec4(coverages.yyy, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 2), vec4(coverages.zzz, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 3), vec4(coverages.www, 1.0));
}
