#version 430

// pathfinder/shaders/gen_clip.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

// Populates a clip vertex buffer for use by the `tile_clip` shader.

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#include "fill.inc.glsl"

// TODO(pcwalton): Improve occupancy!
layout(local_size_x = 16, local_size_y = 16) in;

layout(std430, binding = 0) buffer bClippedPathIndices {
    restrict readonly uint iClippedPathIndices[];
};

layout(std430, binding = 1) buffer bDrawPropagateMetadata {
    restrict readonly uvec4 iDrawPropagateMetadata[];
};

layout(std430, binding = 2) buffer bClipPropagateMetadata {
    restrict readonly uvec4 iClipPropagateMetadata[];
};

layout(std430, binding = 3) buffer bDrawTiles {
    restrict uvec4 iDrawTiles[];
};

layout(std430, binding = 4) buffer bClipTiles {
    restrict uvec4 iClipTiles[];
};

layout(std430, binding = 5) buffer bClipVertexBuffer {
    restrict ivec4 iClipVertexBuffer[];
};

void writeTile(int tileOffset, uvec4 originalTile, int newTileIndex, int newBackdrop) {
    originalTile.y = uint(newTileIndex);
    originalTile.w = uint(originalTile.w & 0xff00ffff) | ((uint(newBackdrop) & 0xff) << 16);
    iDrawTiles[tileOffset] = originalTile;
}

void main() {
    uvec2 tileCoord = uvec2(gl_GlobalInvocationID.xy);

    uint drawPathIndex = iClippedPathIndices[gl_WorkGroupID.z];
    uvec4 drawTileRect     = iDrawPropagateMetadata[drawPathIndex * 2 + 0];
    uvec4 drawPathMetadata = iDrawPropagateMetadata[drawPathIndex * 2 + 1];

    uint clipPathIndex = drawPathMetadata.w;
    uvec4 clipTileRect     = iClipPropagateMetadata[clipPathIndex * 2 + 0];
    uvec4 clipPathMetadata = iClipPropagateMetadata[clipPathIndex * 2 + 1];

    int drawOffset = int(drawPathMetadata.x), clipOffset = int(clipPathMetadata.x);
    ivec2 drawTileOffset2D = ivec2(tileCoord) - ivec2(drawTileRect.xy);
    ivec2 clipTileOffset2D = ivec2(tileCoord) - ivec2(clipTileRect.xy);
    int drawTilesAcross = int(drawTileRect.z - drawTileRect.x);
    int clipTilesAcross = int(clipTileRect.z - clipTileRect.x);
    int drawTileOffset = drawOffset + drawTileOffset2D.x + drawTileOffset2D.y * drawTilesAcross;
    int clipTileOffset = clipOffset + clipTileOffset2D.x + clipTileOffset2D.y * clipTilesAcross;

    bool inBoundsDraw = all(bvec4(greaterThanEqual(tileCoord, drawTileRect.xy),
                                  lessThan        (tileCoord, drawTileRect.zw)));
    if (!inBoundsDraw)
        return;

    bool inBoundsClip = all(bvec4(greaterThanEqual(tileCoord, clipTileRect.xy),
                                  lessThan        (tileCoord, clipTileRect.zw)));

    uvec4 drawTile = iDrawTiles[drawTileOffset];
    int drawTileIndex = int(drawTile.y), drawTileBackdrop = int(drawTile.w << 8) >> 24;

    ivec4 clipTileData = ivec4(-1, 0, -1, 0);
    if (inBoundsClip) {
        uvec4 clipTile = iClipTiles[clipTileOffset];
        int clipTileIndex = int(clipTile.y), clipTileBackdrop = int(clipTile.w << 8) >> 24;

        // Process the tile appropriately.
        if (clipTileIndex >= 0 && drawTileIndex >= 0) {
            // Hard case: We have an alpha tile and a clip tile with masks. Add a job to combine
            // the two masks. Because the mask combining step applies the backdrops, zero out the
            // backdrop in the draw tile itself so that we don't double-count it.
            clipTileData = ivec4(drawTileIndex, drawTileBackdrop, clipTileIndex, clipTileBackdrop);
            writeTile(drawTileOffset, drawTile, drawTileIndex, 0);
        } else if (clipTileIndex >= 0 && drawTileIndex < 0 && drawTileBackdrop != 0) {
            // This is a solid draw tile, but there's a clip applied. Replace it with an alpha tile
            // pointing directly to the clip mask.
            writeTile(drawTileOffset, drawTile, clipTileIndex, clipTileBackdrop);
        } else if (clipTileIndex < 0 && clipTileBackdrop == 0) {
            // This is a blank clip tile. Cull it entirely.
            writeTile(drawTileOffset, drawTile, -1, 0);
        }
    } else {
        // This tile is outside the clip rect, so it's blank. Cull it.
        writeTile(drawTileOffset, drawTile, -1, 0);
    }

    iClipVertexBuffer[drawTileOffset] = clipTileData;
}
