#version 430

// pathfinder/shaders/init.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

// Initializes the tile maps.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

layout(local_size_x = 64) in;

uniform ivec2 uFramebufferTileSize;
uniform int uPathCount;
uniform int uTileCount;

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
    restrict uvec4 iTiles[];
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
    uint tileCount = uint(uTileCount), pathCount = uint(uPathCount);

    uint tileIndex = gl_GlobalInvocationID.x;
    if (tileIndex >= tileCount)
        return;

    uint lowPathIndex = 0, highPathIndex = pathCount;
    int iteration = 0;
    while (iteration < 1024 && lowPathIndex + 1 < highPathIndex) {
        uint midPathIndex = lowPathIndex + (highPathIndex - lowPathIndex) / 2;
        uint midTileIndex = iTilePathInfo[midPathIndex].z;
        if (tileIndex < midTileIndex) {
            highPathIndex = midPathIndex;
        } else {
            lowPathIndex = midPathIndex;
            if (tileIndex == midTileIndex)
                break;
        }
        iteration++;
    }

    uint pathIndex = lowPathIndex;
    uvec4 pathInfo = iTilePathInfo[pathIndex];

    ivec4 tileRect = unpackTileRect(pathInfo);
    uint tileOffset = tileIndex - pathInfo.z;
    uint tileWidth = uint(tileRect.z - tileRect.x);
    ivec2 tileCoords = tileRect.xy + ivec2(tileOffset % tileWidth, tileOffset / tileWidth);

    // Set up the first link.
    atomicMin(iInitialTileMap[tileCoords.x + tileCoords.y * uFramebufferTileSize.x], tileIndex);

    // Find the next link.
    uint nextTilePathIndex = pathIndex + 1;
    uint nextTileIndex = ~0;
    while (nextTilePathIndex < pathCount) {
        uvec4 nextPathInfo = iTilePathInfo[nextTilePathIndex];
        ivec4 nextPathTileRect = unpackTileRect(nextPathInfo);
        if (all(bvec4(greaterThanEqual(tileCoords, nextPathTileRect.xy),
                      lessThan(tileCoords, nextPathTileRect.zw)))) {
            int nextPathTileWidth = nextPathTileRect.z - nextPathTileRect.x;
            nextTileIndex = nextPathInfo.z + uint(nextPathTileRect.x + nextPathTileRect.y *
                                                  nextPathTileWidth);
            break;
        }
        nextTilePathIndex++;
    }

    iTiles[tileIndex] = uvec4((uint(tileCoords.x) & 0xffffu) | (uint(tileCoords.y) << 16),
                              ~0u,
                              pathIndex,
                              pathInfo.w);

    iTileLinkMap[tileIndex] = uvec2(~0, nextTileIndex);
}
