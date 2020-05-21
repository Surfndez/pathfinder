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

layout(std430, binding = 1) buffer bPropagateMetadata {
    restrict readonly uvec4 iPropagateMetadata[];
};

layout(std430, binding = 2) buffer bTiles {
    restrict uvec4 iTiles[];
};

layout(std430, binding = 3) buffer bClipVertexBuffer {
    restrict uint iClipVertexBuffer[];
};

void main() {
    uvec2 tileCoord = uvec2(gl_GlobalInvocationID.xy);

    uint drawPathIndex = iClippedPathIndices[gl_WorkGroupID.z];
    uvec4 drawTileRect     = iPropagateMetadata[drawPathIndex * 2 + 0];
    uvec4 drawPathMetadata = iPropagateMetadata[drawPathIndex * 2 + 1];

    uint clipPathIndex = drawPathMetadata.w;
    uvec4 clipTileRect     = iPropagateMetadata[clipPathIndex * 2 + 0];
    uvec4 clipPathMetadata = iPropagateMetadata[clipPathIndex * 2 + 1];

    uint drawOffset = drawPathMetadata.x, clipOffset = clipPathMetadata.x;
    ivec2 drawTileOffset2D = ivec2(tileCoord) - ivec2(drawTileRect.xy);
    ivec2 clipTileOffset2D = ivec2(tileCoord) - ivec2(clipTileRect.xy);
    int drawTilesAcross = int(drawTileRect.z - drawTileRect.x);
    int clipTilesAcross = int(clipTileRect.z - clipTileRect.x);
    int drawTileOffset = drawTileOffset2D.x + drawTileOffset2D.y * drawTilesAcross;
    int clipTileOffset = clipTileOffset2D.x + clipTileOffset2D.y * clipTilesAcross;

    bool inBoundsDraw = all(bvec4(greaterThanEqual(tileCoord, drawTileRect.xy),
                                  lessThan        (tileCoord, drawTileRect.zw)));
    if (!inBoundsDraw)
        return;

    bool inBoundsClip = all(bvec4(greaterThanEqual(tileCoord, clipTileRect.xy),
                                  lessThan        (tileCoord, clipTileRect.zw)));

    int drawTileIndex = -1, clipTileIndex = -1, clipTileBackdrop = 0;
    if (inBoundsClip) {
        uvec4 drawTile = iTiles[drawTileOffset], clipTile = iTiles[clipTileOffset];
        drawTileIndex = int(drawTile.y);
        clipTileIndex = int(clipTile.y);
        clipTileBackdrop = int(clipTile.w << 8) >> 24;

        // TODO(pcwalton): Handle solid tiles properly.
    }

    iClipVertexBuffer[drawTileOffset * 3 + 0] = drawTileIndex;
    iClipVertexBuffer[drawTileOffset * 3 + 1] = clipTileIndex;
    iClipVertexBuffer[drawTileOffset * 3 + 2] = clipTileBackdrop;
}
