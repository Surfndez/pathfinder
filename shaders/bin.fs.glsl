#version 450

// pathfinder/shaders/bin.fs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

precision highp float;

#ifdef GL_ES
precision highp sampler2D;
#endif

#define OUTCODE_NONE    0x0u
#define OUTCODE_LEFT    0x1u
#define OUTCODE_RIGHT   0x2u
#define OUTCODE_BOTTOM  0x4u
#define OUTCODE_TOP     0x8u

uniform ivec2 uFramebufferSize;

layout(std430, binding = 0) buffer bMetadata {
    restrict readonly ivec4 iMetadata[];
};

// [0]: vertexCount (6)
// [1]: instanceCount (of fills)
// [2]: vertexStart (0)
// [3]: baseInstance (0)
// [4]: alpha tile count
layout(std430, binding = 1) buffer bIndirectDrawParams {
    restrict uint iIndirectDrawParams[];
};

layout(std430, binding = 2) buffer bFills {
    restrict writeonly uint iFills[];
};

layout(std430, binding = 3) buffer bTiles {
    restrict uint iTiles[];
};

in vec2 vFrom;
in vec2 vTo;
flat in uint vPathIndex;

out vec4 oFragColor;

// Cohen-Sutherland

uint computeOutcode(vec2 p, vec4 rect) {
    uint code = OUTCODE_NONE;
    if (p.x < rect.x)
        code |= OUTCODE_LEFT;
    else if (p.x > rect.z)
        code |= OUTCODE_RIGHT;
    if (p.y < rect.y)
        code |= OUTCODE_TOP;
    else if (p.y > rect.w)
        code |= OUTCODE_BOTTOM;
    return code;
}

bool clipLine(vec4 line, vec4 rect, out vec4 outLine) {
    uvec2 outcodes = uvec2(computeOutcode(line.xy, rect), computeOutcode(line.zw, rect));
    while (true) {
        if ((outcodes.x | outcodes.y) == 0u) {
            outLine = line;
            return true;
        }
        if ((outcodes.x & outcodes.y) != 0u) {
            outLine = line;
            return false;
        }

        uint outcode = max(outcodes.x, outcodes.y);
        vec2 p;
        if ((outcode & OUTCODE_TOP) != 0u)
            p = vec2(mix(line.x, line.z, (rect.y - line.y) / (line.w - line.y)), rect.y);
        else if ((outcode & OUTCODE_BOTTOM) != 0u)
            p = vec2(mix(line.x, line.z, (rect.w - line.y) / (line.w - line.y)), rect.w);
        else if ((outcode & OUTCODE_LEFT) != 0u)
            p = vec2(rect.x, mix(line.y, line.w, (rect.x - line.x) / (line.z - line.x)));
        else if ((outcode & OUTCODE_RIGHT) != 0u)
            p = vec2(rect.z, mix(line.y, line.w, (rect.z - line.x) / (line.z - line.x)));

        if (outcode == outcodes.x) {
            line.xy = p;
            outcodes.x = computeOutcode(line.xy, rect);
        } else {
            line.zw = p;
            outcodes.y = computeOutcode(line.zw, rect);
        }
    }
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
#ifdef PF_ORIGIN_UPPER_LEFT
    fragCoord.y = float(uFramebufferSize.y) - fragCoord.y;
#endif

    ivec2 tileCoord = ivec2(fragCoord);
    vec4 tileRect = fragCoord.xyxy + vec4(vec2(-0.5), vec2(0.5));
    vec4 line;
    bool inBounds = clipLine(vec4(vFrom, vTo), tileRect, line);

    if (inBounds) {
        ivec4 pathTileRect = iMetadata[vPathIndex * 2 + 0];
        uint pathTileOffset = uint(iMetadata[vPathIndex * 2 + 1].x);

        ivec2 tileOffset = tileCoord - pathTileRect.xy;
        uint tileIndex = pathTileOffset +
            uint(tileOffset.y * (pathTileRect.z - pathTileRect.x) + tileOffset.x);

        // Allocate an alpha tile if necessary.
        // FIXME(pcwalton): Should I use `atomicAdd(..., 0)` instead?
        uint alphaTileIndex = iTiles[tileIndex * 4 + 1];
        if (alphaTileIndex == 0) {
            uint trialAlphaTileIndex = atomicAdd(iIndirectDrawParams[4], 1);
            alphaTileIndex = atomicCompSwap(iTiles[tileIndex * 4 + 1], 0, trialAlphaTileIndex);
            if (alphaTileIndex == 0) {
                // We won the race.
                alphaTileIndex = trialAlphaTileIndex;
                iTiles[tileIndex * 4 + 1] = alphaTileIndex;
            }
        }

        vec4 localLine = line - tileRect.xyxy;
        uvec4 scaledLocalLine = uvec4(localLine * vec4(256.0));

        // Bump instance count.
        uint fillIndex = atomicAdd(iIndirectDrawParams[1], 1);

        // Write fill.
        iFills[fillIndex * 3 + 0] = scaledLocalLine.x | (scaledLocalLine.y << 16);
        iFills[fillIndex * 3 + 1] = scaledLocalLine.z | (scaledLocalLine.w << 16);
        iFills[fillIndex * 3 + 2] = alphaTileIndex;
    }

    // FIXME(pcwalton): Don't bind a color attachment if not necessary!
    oFragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
