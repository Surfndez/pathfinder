#version 430

// pathfinder/shaders/tile_fill.fs.glsl
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

uniform sampler2D uColorTexture0;
uniform sampler2D uMaskTexture0;
uniform sampler2D uDestTexture;
uniform sampler2D uGammaLUT;
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

in vec2 vTileSubCoord;
flat in uint vMaskTileIndex0;
flat in int vMaskTileBackdrop0;
in vec2 vColorTexCoord0;
in vec4 vBaseColor;
in float vTileCtrl;

out vec4 oFragColor;

#include "fill.inc.glsl"
#include "fill_compute.inc.glsl"
#include "tile.inc.glsl"

vec4 calculateColor(int tileCtrl, int ctrl) {
    float maskAlpha = 1.0;
    int maskCtrl0 = (ctrl >> COMBINER_CTRL_MASK_SHIFT) & COMBINER_CTRL_MASK_ENABLE;
    int maskTileCtrl0 = (tileCtrl >> TILE_CTRL_MASK_0_SHIFT) & TILE_CTRL_MASK_MASK;
    uint maskTileIndex0 = vMaskTileIndex0;
    if (maskCtrl0 != 0 && maskTileCtrl0 != 0) {
        ivec2 tileSubCoord = ivec2(floor(vTileSubCoord));
        vec4 alphas = calculateFillAlpha(tileSubCoord, maskTileIndex0) + float(vMaskTileBackdrop0);
        maskAlpha = alphas.x;
    }
    return calculateColorWithMaskAlpha(maskAlpha,
                                       vBaseColor,
                                       vColorTexCoord0,
                                       gl_FragCoord.xy,
                                       ctrl);
}

// Entry point
//
// TODO(pcwalton): Generate this dynamically.

void main() {
    oFragColor = calculateColor(int(vTileCtrl), uCtrl);
    //oFragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
