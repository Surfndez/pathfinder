#version 330

// pathfinder/shaders/tile.vs.glsl
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

uniform mat4 uTransform;
uniform vec2 uTileSize;
uniform sampler2D uTextureMetadata;
uniform ivec2 uTextureMetadataSize;

in ivec2 aTileOffset;
in ivec2 aTileOrigin;
in uvec2 aMaskTexCoord0;
in ivec2 aMaskBackdrop;
in int aColor;
in int aTileCtrl;

out vec3 vMaskTexCoord0;
out vec2 vColorTexCoord0;
out vec4 vBaseColor;
out float vTileCtrl;

#include "tile_vertex.inc.glsl"

void main() {
    vec2 tileOrigin = vec2(aTileOrigin), tileOffset = vec2(aTileOffset);
    vec2 position = (tileOrigin + tileOffset) * uTileSize;

    vec2 maskTexCoord0 = vec2(aMaskTexCoord0);
    maskTexCoord0 = (maskTexCoord0 + tileOffset) * uTileSize;

    mat2 colorTexMatrix0;
    vec4 colorTexOffsets;
    vec4 baseColor;
    lookupTextureMetadata(aColor, colorTexMatrix0, colorTexOffsets, baseColor);

    vColorTexCoord0 = colorTexMatrix0 * position + colorTexOffsets.xy;
    vMaskTexCoord0 = vec3(maskTexCoord0, float(aMaskBackdrop.x));
    vBaseColor = baseColor;
    vTileCtrl = float(aTileCtrl);
    gl_Position = uTransform * vec4(position, 0.0, 1.0);
}
