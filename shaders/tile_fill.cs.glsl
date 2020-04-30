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
precision highp sampler2D;

layout(local_size_x = 16, local_size_y = 4) in;

layout(rgba8) uniform image2D uDestImage;
uniform sampler2D uTextureMetadata;
uniform ivec2 uTextureMetadataSize;
uniform sampler2D uColorTexture0;
uniform sampler2D uMaskTexture0;
uniform sampler2D uGammaLUT;
uniform vec2 uTileSize;
uniform vec4 uFilterParams0;
uniform vec4 uFilterParams1;
uniform vec4 uFilterParams2;
uniform vec2 uFramebufferSize;
uniform vec2 uColorTextureSize0;
uniform int uCtrl;
uniform sampler2D uAreaLUT;

layout(std430, binding = 0) buffer bFills {
    restrict readonly uvec2 iFills[];
};

layout(std430, binding = 1) buffer bNextFills {
    restrict readonly int iNextFills[];
};

layout(std430, binding = 2) buffer bFillTileMap {
    restrict readonly int iFillTileMap[];
};

layout(std430, binding = 3) buffer bTiles {
    restrict readonly uint iTiles[];
};

layout(std430, binding = 4) buffer bNextTiles {
    restrict readonly int iNextTiles[];
};

layout(std430, binding = 5) buffer bFirstTiles {
    restrict readonly int iFirstTiles[];
};

#include "fill.inc.glsl"
#include "fill_compute.inc.glsl"
#include "tile.inc.glsl"
#include "tile_vertex.inc.glsl"

// Entry point

void main() {
    int maskCtrl0 = (uCtrl >> COMBINER_CTRL_MASK_SHIFT) & COMBINER_CTRL_MASK_ENABLE;

    vec4 colors[4] = {vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)};
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID.xy) * ivec2(1, 4);
    ivec2 tileOrigin = ivec2(0);

    int tileIndex = iFirstTiles[gl_WorkGroupID.z];
    int overlapCount = 0;

    while (tileIndex >= 0) {
        overlapCount++;

        uint tileCoord    = iTiles[tileIndex * 3 + 0];
        uint maskTexCoord = iTiles[tileIndex * 3 + 1];
        uint colorCtrl    = iTiles[tileIndex * 3 + 2];

        tileOrigin = ivec2(int(tileCoord & 0xffff), int(tileCoord >> 16));

        int ctrl = int(uCtrl);
        int tileColor = int(colorCtrl & 0xffff);
        int tileCtrl = int(colorCtrl >> 16);

        mat2 colorTexMatrix0;
        vec4 colorTexOffsets;
        vec4 baseColor;
        lookupTextureMetadata(tileColor, colorTexMatrix0, colorTexOffsets, baseColor);

        int maskTileCtrl0 = (tileCtrl >> TILE_CTRL_MASK_0_SHIFT) & TILE_CTRL_MASK_MASK;

        vec4 maskAlphas = vec4(1.0);
        if (maskCtrl0 != 0 && maskTileCtrl0 != 0) {
            uint maskTileIndex0 = maskTexCoord & 0xffff;
            int maskTileBackdrop0 = int(maskTexCoord << 8) >> 24;
            maskAlphas = clamp(abs(calculateFillAlpha(tileSubCoord, maskTileIndex0) +
                float(maskTileBackdrop0)), 0.0, 1.0);
        }

        for (int yOffset = 0; yOffset < 4; yOffset++) {
            // TODO(pcwalton): Blend if necessary.
            ivec2 fragCoordI = tileOrigin * ivec2(uTileSize) + tileSubCoord + ivec2(0, yOffset);
            vec2 fragCoord = vec2(fragCoordI) + vec2(0.5);
            vec2 colorTexCoord0 = colorTexMatrix0 * fragCoord + colorTexOffsets.xy;
            vec4 color = calculateColorWithMaskAlpha(maskAlphas[yOffset],
                                                     baseColor,
                                                     colorTexCoord0,
                                                     fragCoord,
                                                     ctrl);
            colors[yOffset] = colors[yOffset] * (1.0 - color.a) + color;
        }

        tileIndex = iNextTiles[tileIndex];
    }

    for (int yOffset = 0; yOffset < 4; yOffset++) {
        ivec2 fragCoord = tileOrigin * ivec2(uTileSize) + tileSubCoord + ivec2(0, yOffset);

        // TODO(pcwalton): Other blending modes.
        vec4 color = colors[yOffset];
        if (color.a < 1.0)
            color = imageLoad(uDestImage, fragCoord) * (1.0 - color.a) + color;
        imageStore(uDestImage, fragCoord, color);
    }
}
