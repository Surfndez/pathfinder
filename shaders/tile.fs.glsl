#version 330

// pathfinder/shaders/tile.fs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

//      Mask UV 0         Mask UV 1
//          +                 +
//          |                 |
//    +-----v-----+     +-----v-----+
//    |           | MIN |           |
//    |  Mask  0  +----->  Mask  1  +------+
//    |           |     |           |      |
//    +-----------+     +-----------+      v       +-------------+
//                                       Apply     |             |       GPU
//                                       Mask +---->  Composite  +---->Blender
//                                         ^       |             |
//    +-----------+     +-----------+      |       +-------------+
//    |           |     |           |      |
//    |  Color 0  +----->  Color 1  +------+
//    |  Filter   |  ×  |           |
//    |           |     |           |
//    +-----^-----+     +-----^-----+
//          |                 |
//          +                 +
//     Color UV 0        Color UV 1

#extension GL_GOOGLE_include_directive : enable

precision highp float;

#define COMBINER_CTRL_MASK_0_MASK               0x003
#define COMBINER_CTRL_MASK_1_MASK               0x004
#define COMBINER_CTRL_COLOR_0_FILTER_MASK       0x038
#define COMBINER_CTRL_COLOR_1_MULTIPLY          0x040
#define COMBINER_CTRL_COMPOSITE_MASK            0xf80

#define COMBINER_CTRL_MASK_WINDING              0x1
#define COMBINER_CTRL_MASK_EVEN_ODD             0x2

#define COMBINER_CTRL_FILTER_RADIAL_GRADIENT    0x1
#define COMBINER_CTRL_FILTER_TEXT_NO_GAMMA      0x2
#define COMBINER_CTRL_FILTER_TEXT_GAMMA         0x3
#define COMBINER_CTRL_FILTER_BLUR_X             0x4
#define COMBINER_CTRL_FILTER_BLUR_Y             0x5

#define COMBINER_CTRL_COMPOSITE_SRC_OVER        0x01
#define COMBINER_CTRL_COMPOSITE_SRC_IN          0x02
#define COMBINER_CTRL_COMPOSITE_SRC_OUT         0x03
#define COMBINER_CTRL_COMPOSITE_SRC_ATOP        0x04
#define COMBINER_CTRL_COMPOSITE_DEST_OVER       0x05
#define COMBINER_CTRL_COMPOSITE_DEST_IN         0x06
#define COMBINER_CTRL_COMPOSITE_DEST_OUT        0x07
#define COMBINER_CTRL_COMPOSITE_DEST_ATOP       0x08
#define COMBINER_CTRL_COMPOSITE_LIGHTER         0x09
#define COMBINER_CTRL_COMPOSITE_COPY            0x0a
#define COMBINER_CTRL_COMPOSITE_XOR             0x0b
#define COMBINER_CTRL_COMPOSITE_MULTIPLY        0x0c
#define COMBINER_CTRL_COMPOSITE_SCREEN          0x0d
#define COMBINER_CTRL_COMPOSITE_OVERLAY         0x0e
#define COMBINER_CTRL_COMPOSITE_DARKEN          0x0f
#define COMBINER_CTRL_COMPOSITE_LIGHTEN         0x10
#define COMBINER_CTRL_COMPOSITE_COLOR_DODGE     0x11
#define COMBINER_CTRL_COMPOSITE_COLOR_BURN      0x12
#define COMBINER_CTRL_COMPOSITE_HARD_LIGHT      0x13
#define COMBINER_CTRL_COMPOSITE_SOFT_LIGHT      0x14
#define COMBINER_CTRL_COMPOSITE_DIFFERENCE      0x15
#define COMBINER_CTRL_COMPOSITE_EXCLUSION       0x16
#define COMBINER_CTRL_COMPOSITE_HUE             0x17
#define COMBINER_CTRL_COMPOSITE_SATURATION      0x18
#define COMBINER_CTRL_COMPOSITE_COLOR           0x19
#define COMBINER_CTRL_COMPOSITE_LUMINOSITY      0x1a

#define COMBINER_CTRL_MASK_0_SHIFT              0
#define COMBINER_CTRL_MASK_1_SHIFT              2
#define COMBINER_CTRL_COLOR_0_FILTER_SHIFT      3
#define COMBINER_CTRL_COLOR_1_MULTIPLY_SHIFT    6
#define COMBINER_CTRL_COMPOSITE_SHIFT           7

uniform sampler2D uDestTexture;
uniform sampler2D uColorTexture0;
uniform sampler2D uColorTexture1;
uniform sampler2D uMaskTexture0;
uniform sampler2D uMaskTexture1;
uniform sampler2D uGammaLUT;
uniform vec4 uFilterParams0;
uniform vec4 uFilterParams1;
uniform vec2 uDestTextureSize;
uniform int uCtrl;

in vec3 vMaskTexCoord0;
in vec3 vMaskTexCoord1;
in vec2 vColorTexCoord0;
in vec2 vColorTexCoord1;

out vec4 oFragColor;

float sampleMask(float maskAlpha,
                 sampler2D maskTexture,
                 vec3 maskTexCoord,
                 int maskCtrl) {
    if (maskCtrl == 0)
        return maskAlpha;
    float coverage = texture(maskTexture, maskTexCoord.xy).r + maskTexCoord.z;
    if ((maskCtrl & COMBINER_CTRL_MASK_WINDING) != 0)
        coverage = abs(coverage);
    else
        coverage = 1.0 - abs(1.0 - mod(coverage, 2.0));
    return min(maskAlpha, coverage);
}

vec4 sampleColor(sampler2D colorTexture, vec2 colorTexCoord) {
    return texture(colorTexture, colorTexCoord);
}

vec2 computeColorTexCoord(vec2 colorTexCoord,
                          int colorFilter,
                          vec4 filterParams0,
                          vec4 filterParams1) {
    return colorTexCoord;
}

vec4 filterColor(sampler2D colorTexture,
                 vec2 colorTexCoord,
                 int colorFilter,
                 vec4 filterParams0,
                 vec4 filterParams1) {
    colorTexCoord = computeColorTexCoord(colorTexCoord, colorFilter, filterParams0, filterParams1);
    return sampleColor(colorTexture, colorTexCoord);
}

vec4 composite(vec4 color, sampler2D destTexture, vec2 fragCoord) {
    // TODO(pcwalton)
    return color;
}

void main() {
    // Sample mask.
    int maskCtrl0 = (uCtrl & COMBINER_CTRL_MASK_0_MASK) >> COMBINER_CTRL_MASK_0_SHIFT;
    int maskCtrl1 = (uCtrl & COMBINER_CTRL_MASK_1_MASK) >> COMBINER_CTRL_MASK_1_SHIFT;
    float maskAlpha = 1.0;
    maskAlpha = sampleMask(maskAlpha, uMaskTexture0, vMaskTexCoord0, maskCtrl0);
    maskAlpha = sampleMask(maskAlpha, uMaskTexture1, vMaskTexCoord1, maskCtrl1);

    // Sample color.
    int color0Filter = (uCtrl & COMBINER_CTRL_COLOR_0_FILTER_MASK) >> COMBINER_CTRL_MASK_0_SHIFT;
    vec4 color = filterColor(uColorTexture0,
                             vColorTexCoord0,
                             color0Filter,
                             uFilterParams0,
                             uFilterParams1);
    if ((uCtrl & COMBINER_CTRL_COLOR_1_MULTIPLY) != 0)
        color *= sampleColor(uColorTexture1, vColorTexCoord1);

    // Apply mask.
    color *= vec4(maskAlpha);

    // Apply composite.
    oFragColor = composite(color, uDestTexture, gl_FragCoord.xy);
}
