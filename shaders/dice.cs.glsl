#version 430

// pathfinder/shaders/dice.cs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

#define BIN_WORKGROUP_SIZE  64

#define FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC   0x80000000u
#define FLAGS_PATH_INDEX_CURVE_IS_CUBIC       0x40000000u
#define FLAGS_PATH_INDEX_PATH_INDEX_BITMASK   0xbfffffffu

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

layout(local_size_x = 64) in;

struct Segment {
    vec4 line;
    uvec4 pathIndex;
};

layout(std430, binding = 0) buffer bComputeIndirectParams {
    // [0]: number of x workgroups
    // [1]: number of y workgroups (always 1)
    // [2]: number of z workgroups (always 1)
    // [3]: unused
    // [4]: number of input indices
    // [5]: number of output segments
    restrict uint iComputeIndirectParams[];
};

layout(std430, binding = 1) buffer bPoints {
    restrict readonly vec2 iPoints[];
};

layout(std430, binding = 2) buffer bInputIndices {
    restrict readonly uvec2 iInputIndices[];
};

layout(std430, binding = 3) buffer bOutputSegments {
    restrict Segment iOutputSegments[];
};

void emitLineSegment(vec4 lineSegment, uint pathIndex) {
    uint outputSegmentIndex = atomicAdd(iComputeIndirectParams[5], 1);
    if (outputSegmentIndex % BIN_WORKGROUP_SIZE == 0)
        atomicAdd(iComputeIndirectParams[0], 1);

    iOutputSegments[outputSegmentIndex].line = lineSegment;
    iOutputSegments[outputSegmentIndex].pathIndex.x = pathIndex;
}

void main() {
    uint inputIndex = gl_GlobalInvocationID.x;
    if (inputIndex >= iComputeIndirectParams[4])
        return;

    uvec2 inputIndices = iInputIndices[inputIndex];
    uint fromPointIndex = inputIndices.x, flagsPathIndex = inputIndices.y;
    uint pathIndex = flagsPathIndex & FLAGS_PATH_INDEX_PATH_INDEX_BITMASK;

    uint toPointIndex = fromPointIndex;
    if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_CUBIC) != 0u)
        toPointIndex += 3;
    else if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC) != 0u)
        toPointIndex += 2;
    else
        toPointIndex += 1;

    vec4 baseline = vec4(iPoints[fromPointIndex], iPoints[toPointIndex]);
    if ((flagsPathIndex & (FLAGS_PATH_INDEX_CURVE_IS_CUBIC |
                           FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC)) == 0) {
        emitLineSegment(baseline, pathIndex);
        return;
    }

    // Get control points. Degree elevate if quadratic.
    vec2 ctrl0 = iPoints[fromPointIndex + 1];
    vec4 ctrl;
    if ((flagsPathIndex & FLAGS_PATH_INDEX_CURVE_IS_QUADRATIC) != 0) {
        vec2 ctrl0_2 = ctrl0 * vec2(2.0);
        ctrl = (baseline + (ctrl0 * vec2(2.0)).xyxy) * vec4(1.0 / 3.0);
    } else {
        ctrl = vec4(ctrl0, iPoints[fromPointIndex + 2]);
    }

    // TODO(pcwalton)
    emitLineSegment(vec4(baseline.xy, ctrl.xy), pathIndex);
    emitLineSegment(ctrl, pathIndex);
    emitLineSegment(vec4(ctrl.zw, baseline.zw), pathIndex);
}
