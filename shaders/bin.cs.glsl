#version 430

// pathfinder/shaders/bin.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

#define MAX_ITERATIONS          1024u

#define STEP_DIRECTION_NONE     0
#define STEP_DIRECTION_X        1
#define STEP_DIRECTION_Y        2

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

layout(local_size_x = 64) in;

struct Segment {
    vec4 line;
    uvec4 pathIndex;
};

layout(std430, binding = 0) buffer bSegments {
    restrict readonly Segment iSegments[];
};

layout(std430, binding = 1) buffer bMetadata {
    restrict readonly ivec4 iMetadata[];
};

// [0]: vertexCount (6)
// [1]: instanceCount (of fills)
// [2]: vertexStart (0)
// [3]: baseInstance (0)
// [4]: alpha tile count
layout(std430, binding = 2) buffer bIndirectDrawParams {
    restrict uint iIndirectDrawParams[];
};

layout(std430, binding = 3) buffer bFills {
    restrict writeonly uint iFills[];
};

layout(std430, binding = 4) buffer bTiles {
    restrict uint iTiles[];
};

bool computeTileIndex(ivec2 tileCoords,
                      ivec4 pathTileRect,
                      uint pathTileOffset,
                      out uint outTileIndex) {
    ivec2 offsetCoords = tileCoords - pathTileRect.xy;
    outTileIndex = pathTileOffset + offsetCoords.x +
        offsetCoords.y * (pathTileRect.z - pathTileRect.x);
    return all(bvec4(greaterThanEqual(tileCoords, pathTileRect.xy),
                     lessThan(tileCoords, pathTileRect.zw)));
}

void addFill(vec4 lineSegment, ivec2 tileCoords, ivec4 pathTileRect, uint pathTileOffset) {
    // Compute tile offset. If out of bounds, cull.
    uint tileIndex;
    if (!computeTileIndex(tileCoords, pathTileRect, pathTileOffset, tileIndex))
        return;

    // Clip line.
    uvec4 scaledLocalLine = uvec4((lineSegment - vec4(tileCoords.xyxy * ivec4(16))) * vec4(256.0));

    // Allocate an alpha tile if necessary.
    if (atomicCompSwap(iTiles[tileIndex * 4 + 1], uint(-1), 0u) == uint(-1))
        atomicExchange(iTiles[tileIndex * 4 + 1], atomicAdd(iIndirectDrawParams[4], 1));

    // Bump instance count.
    uint fillIndex = atomicAdd(iIndirectDrawParams[1], 1);

    // Write fill.
    iFills[fillIndex * 3 + 0] = scaledLocalLine.x | (scaledLocalLine.y << 16);
    iFills[fillIndex * 3 + 1] = scaledLocalLine.z | (scaledLocalLine.w << 16);
    iFills[fillIndex * 3 + 2] = tileIndex;
}

void adjustBackdrop(int backdropDelta, ivec2 tileCoords, ivec4 pathTileRect, uint pathTileOffset) {
    uint tileIndex;
    if (computeTileIndex(tileCoords, pathTileRect, pathTileOffset, tileIndex))
        atomicAdd(iTiles[tileIndex * 4 + 3], backdropDelta << 24);
}

void main() {
    uint segmentIndex = gl_GlobalInvocationID.x;
    vec4 lineSegment = iSegments[segmentIndex].line;
    uint pathIndex = iSegments[segmentIndex].pathIndex.x;

    ivec4 pathTileRect = iMetadata[pathIndex * 2 + 0];
    uint pathTileOffset = uint(iMetadata[pathIndex * 2 + 1].x);

    // Following is a straight port of `process_line_segment()`:

    ivec2 tileSize = ivec2(16);

    ivec4 tileLineSegment = ivec4(floor(lineSegment / vec4(tileSize.xyxy)));
    ivec2 fromTileCoords = tileLineSegment.xy, toTileCoords = tileLineSegment.zw;

    vec2 vector = lineSegment.zw - lineSegment.xy;
    vec2 vectorIsNegative = vec2(vector.x < 0.0 ? -1.0 : 0.0, vector.y < 0.0 ? -1.0 : 0.0);
    ivec2 tileStep = ivec2(vector.x < 0.0 ? -1 : 1, vector.y < 0.0 ? -1 : 1);

    vec2 firstTileCrossing = vec2((fromTileCoords + ivec2(vector.x >= 0.0 ? 1 : 0,
                                                          vector.y >= 0.0 ? 1 : 0)) * tileSize);

    vec2 tMax = (firstTileCrossing - lineSegment.xy) / vector;
    vec2 tDelta = abs(tileSize / vector);

    vec2 currentPosition = lineSegment.xy;
    ivec2 tileCoords = fromTileCoords;
    int lastStepDirection = STEP_DIRECTION_NONE;
    uint iteration = 0;

    while (iteration < MAX_ITERATIONS) {
        int nextStepDirection;
        if (tMax.x < tMax.y)
            nextStepDirection = STEP_DIRECTION_X;
        else if (tMax.x > tMax.y)
            nextStepDirection = STEP_DIRECTION_Y;
        else if (tileStep.x > 0.0)
            nextStepDirection = STEP_DIRECTION_X;
        else
            nextStepDirection = STEP_DIRECTION_Y;

        float nextT = min(nextStepDirection == STEP_DIRECTION_X ? tMax.x : tMax.y, 1.0);

        // If we've reached the end tile, don't step at all.
        if (tileCoords == toTileCoords)
            nextStepDirection = STEP_DIRECTION_NONE;

        vec2 nextPosition = mix(lineSegment.xy, lineSegment.zw, nextT);
        vec4 clippedLineSegment = vec4(currentPosition, nextPosition);
        addFill(clippedLineSegment, tileCoords, pathTileRect, pathTileOffset);

        // Add extra fills if necessary.
        vec4 auxiliarySegment;
        bool haveAuxiliarySegment = false;
        if (tileStep.y < 0 && nextStepDirection == STEP_DIRECTION_Y) {
            auxiliarySegment = vec4(clippedLineSegment.zw, vec2(tileCoords * tileSize));
            haveAuxiliarySegment = true;
        } else if (tileStep.y > 0 && lastStepDirection == STEP_DIRECTION_Y) {
            auxiliarySegment = vec4(vec2(tileCoords * tileSize), clippedLineSegment.xy);
            haveAuxiliarySegment = true;
        }
        if (haveAuxiliarySegment)
            addFill(auxiliarySegment, tileCoords, pathTileRect, pathTileOffset);

        // Adjust backdrop if necessary.
        int backdropAdjustment = 0;
        if (tileStep.x < 0 && lastStepDirection == STEP_DIRECTION_X)
            backdropAdjustment = 1;
        else if (tileStep.x > 0 && nextStepDirection == STEP_DIRECTION_X)
            backdropAdjustment = -1;
        // TODO(pcwalton): Adjust backdrop!
        adjustBackdrop(backdropAdjustment, tileCoords, pathTileRect, pathTileOffset);

        // Take a step.
        if (nextStepDirection == STEP_DIRECTION_X) {
            tMax.x += tDelta.x;
            tileCoords.x += tileStep.x;
        } else if (nextStepDirection == STEP_DIRECTION_Y) {
            tMax.y += tDelta.y;
            tileCoords.y += tileStep.y;
        } else if (nextStepDirection == STEP_DIRECTION_NONE) {
            break;
        }

        currentPosition = nextPosition;
        lastStepDirection = nextStepDirection;

        iteration++;
    }
}
