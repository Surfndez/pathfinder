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

// TODO(pcwalton): Improve occupancy!
layout(local_size_x = 256) in;

uniform ivec2 uFramebufferTileSize;

layout(std430, binding = 0) buffer bDrawMetadata {
    restrict readonly uvec4 iDrawMetadata[];
};

layout(std430, binding = 1) buffer bClipMetadata {
    restrict readonly uvec4 iClipMetadata[];
};

layout(std430, binding = 2) buffer bBackdrops {
    restrict readonly int iBackdrops[];
};

layout(std430, binding = 3) buffer bDrawTiles {
    restrict uint iDrawTiles[];
};

layout(std430, binding = 4) buffer bClipTiles {
    restrict uint iClipTiles[];
};

layout(std430, binding = 5) buffer bClipVertexBuffer {
    restrict ivec4 iClipVertexBuffer[];
};

layout(std430, binding = 6) buffer bZBuffer {
    restrict int iZBuffer[];
};

uint calculateTileIndex(uint bufferOffset, uvec4 tileRect, uvec2 tileCoord) {
    return bufferOffset + tileCoord.y * (tileRect.z - tileRect.x) + tileCoord.x;
}

void main() {
    uint drawPathIndex = gl_WorkGroupID.y;
    uint tileX = uint(gl_LocalInvocationID.x);

    uvec4 drawTileRect = iDrawMetadata[drawPathIndex * 2 + 0];
    uvec4 drawOffsets = iDrawMetadata[drawPathIndex * 2 + 1];
    uvec2 drawTileSize = drawTileRect.zw - drawTileRect.xy;
    uint drawTileBufferOffset = drawOffsets.x, drawBackdropOffset = drawOffsets.y;
    bool zWrite = drawOffsets.z != 0;

    if (tileX >= drawTileSize.x)
        return;

    int clipPathIndex = int(drawOffsets.w);
    uvec4 clipTileRect = uvec4(0u), clipOffsets = uvec4(0u);
    if (clipPathIndex >= 0) {
        clipTileRect = iClipMetadata[clipPathIndex * 2 + 0];
        clipOffsets = iClipMetadata[clipPathIndex * 2 + 1];
    }
    uint clipTileBufferOffset = clipOffsets.x, clipBackdropOffset = clipOffsets.y;

    int currentBackdrop = iBackdrops[drawBackdropOffset + tileX];
    for (uint tileY = 0; tileY < drawTileSize.y; tileY++) {
        uvec2 drawTileCoord = uvec2(tileX, tileY);
        uint drawTileIndex = calculateTileIndex(drawTileBufferOffset, drawTileRect, drawTileCoord);

        int drawAlphaTileIndex = int(iDrawTiles[drawTileIndex * 4 + 1]);
        uint drawTileWord = iDrawTiles[drawTileIndex * 4 + 3];

        int delta = int(drawTileWord) >> 24;
        int drawTileBackdrop = currentBackdrop;

        // Handle clip if necessary.
        if (clipPathIndex >= 0) {
            uvec2 tileCoord = drawTileCoord + drawTileRect.xy;
            ivec4 clipTileData = ivec4(-1, 0, -1, 0);
            if (all(bvec4(greaterThanEqual(tileCoord, clipTileRect.xy),
                          lessThan        (tileCoord, clipTileRect.zw)))) {
                uvec2 clipTileCoord = tileCoord - clipTileRect.xy;
                uint clipTileIndex = calculateTileIndex(clipTileBufferOffset,
                                                        clipTileRect,
                                                        clipTileCoord);

                int clipAlphaTileIndex = int(iClipTiles[clipTileIndex * 4 + 1]);
                uint clipTileWord = iClipTiles[clipTileIndex * 4 + 3];
                int clipTileBackdrop = (int(clipTileWord) << 8) >> 24;

                if (clipAlphaTileIndex >= 0 && drawAlphaTileIndex >= 0) {
                    // Hard case: We have an alpha tile and a clip tile with masks. Add a job to
                    // combine the two masks. Because the mask combining step applies the
                    // backdrops, zero out the backdrop in the draw tile itself so that we don't
                    // double-count it.
                    clipTileData = ivec4(drawAlphaTileIndex,
                                         drawTileBackdrop,
                                         clipAlphaTileIndex,
                                         clipTileBackdrop);
                    drawTileBackdrop = 0;
                } else if (clipAlphaTileIndex >= 0 &&
                           drawAlphaTileIndex < 0 &&
                           drawTileBackdrop != 0) {
                    // This is a solid draw tile, but there's a clip applied. Replace it with an
                    // alpha tile pointing directly to the clip mask.
                    drawAlphaTileIndex = clipAlphaTileIndex;
                    drawTileBackdrop = clipTileBackdrop;
                } else if (clipAlphaTileIndex < 0 && clipTileBackdrop == 0) {
                    // This is a blank clip tile. Cull the draw tile entirely.
                    drawAlphaTileIndex = -1;
                    drawTileBackdrop = 0;
                }
            } else {
                // This draw tile is outside the clip path bounding rect. Cull the draw tile.
                drawAlphaTileIndex = -1;
                drawTileBackdrop = 0;
            }

            iClipVertexBuffer[drawTileIndex] = clipTileData;
        }

        iDrawTiles[drawTileIndex * 4 + 1] = drawAlphaTileIndex;
        iDrawTiles[drawTileIndex * 4 + 3] = (drawTileWord & 0x00ffffff) |
            ((uint(drawTileBackdrop) & 0xff) << 24);

        // Write to Z-buffer if necessary.
        if (zWrite && drawTileBackdrop != 0 && drawAlphaTileIndex < 0) {
            ivec2 tileCoord = ivec2(tileX, tileY) + ivec2(drawTileRect.xy);
            int zBufferIndex = tileCoord.y * uFramebufferTileSize.x + tileCoord.x;
            atomicMax(iZBuffer[zBufferIndex], int(drawPathIndex));
        }

        currentBackdrop += delta;
    }
}
