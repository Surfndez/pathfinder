#version 430

// pathfinder/shaders/fill.cs.glsl
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
precision highp sampler2D;

layout(local_size_x = 16, local_size_y = 4) in;

uniform writeonly image2D uDest;
uniform sampler2D uAreaLUT;
uniform int uFirstTileIndex;

layout(std430, binding = 0) buffer bFills {
    restrict readonly uvec2 iFills[];
};

layout(std430, binding = 1) buffer bNextFills {
    restrict readonly int iNextFills[];
};

layout(std430, binding = 2) buffer bFillTileMap {
    restrict readonly int iFillTileMap[];
};

#include "fill.inc.glsl"
#include "fill_compute.inc.glsl"

void main() {
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID.xy) * ivec2(1, 4);
    uint tileIndex = uint(uFirstTileIndex) + gl_WorkGroupID.z;
    vec4 coverages = calculateFillAlpha(tileSubCoord, tileIndex);

    ivec2 tileOrigin = calculateTileOrigin(tileIndex);
    ivec2 destCoord = tileOrigin + tileSubCoord;
    imageStore(uDest, destCoord, coverages);
}
