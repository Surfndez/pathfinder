#version 430

// pathfinder/shaders/init_list.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

// Initializes the linked list running through alpha tiles.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

layout(local_size_x = 2, local_size_y = 2) in;

uniform ivec2 uFramebufferTileSize;
uniform int uPathCount;

layout(std430, binding = 0) buffer bTilePathInfo {
    // x: tile upper left, 16-bit packed x/y
    // y: tile lower right, 16-bit packed x/y
    // z: first tile index in this path
    // w: color/ctrl/backdrop word
    restrict readonly uvec4 iTilePathInfo[];
};

layout(std430, binding = 1) buffer bTiles {
    // x: tile coords, 16-bit packed x/y
    // y: alpha tile ID (initialized to -1)
    // z: path ID
    // w: color/ctrl/backdrop word
    restrict readonly uvec4 iTiles[];
};

layout(std430, binding = 2) buffer bTileLinkMap {
    restrict uvec2 iTileLinkMap[];
};

layout(std430, binding = 3) buffer bInitialTileMap {
    restrict uint iInitialTileMap[];
};

ivec4 unpackTileRect(uvec4 pathInfo) {
    ivec2 packedTileRect = ivec2(pathInfo.xy);
    return ivec4((packedTileRect.x << 16) >> 16, packedTileRect.x >> 16,
                 (packedTileRect.y << 16) >> 16, packedTileRect.y >> 16);
}

void main() {
    ivec2 tileCoords = ivec2(gl_GlobalInvocationID.xy);
    if (tileCoords.x >= uFramebufferTileSize.x || tileCoords.y >= uFramebufferTileSize.y)
        return;

    int prevTileIndex = -1;
    for (uint pathIndex = 0; pathIndex < uint(uPathCount); pathIndex++) {
        uvec4 pathInfo = iTilePathInfo[pathIndex];
        ivec4 tileRect = unpackTileRect(pathInfo);
        if (all(bvec4(greaterThanEqual(tileCoords, tileRect.xy),
                      lessThan(tileCoords, tileRect.zw)))) {
            int tileWidth = tileRect.z - tileRect.x;
            int tileIndex = int(pathInfo.z) + tileCoords.x + tileCoords.y * tileWidth;
            if (prevTileIndex < 0)
                iInitialTileMap[tileCoords.x + uFramebufferTileSize.x * tileCoords.y] = tileIndex;
            else
                iTileLinkMap[prevTileIndex].y = tileIndex;
            prevTileIndex = tileIndex;
        }
    }

    if (prevTileIndex < 0)
        iInitialTileMap[tileCoords.x + uFramebufferTileSize.x * tileCoords.y] = -1;
}
