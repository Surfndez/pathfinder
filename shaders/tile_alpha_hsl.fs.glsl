#version 330

// pathfinder/shaders/tile_alpha_hsl.fs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

#extension GL_GOOGLE_include_directive : enable

#define BLEND_TERM_DEST 0
#define BLEND_TERM_SRC  1

precision highp float;

uniform sampler2D uStencilTexture;
uniform sampler2D uPaintTexture;
uniform sampler2D uDest;
uniform ivec3 uBlendHSL;

in vec2 vColorTexCoord;
in vec2 vMaskTexCoord;

out vec4 oFragColor;

/*
vec4 convertRGBAToHSLA(vec4 rgba) {
    
}
*/

void main() {
    float coverage = texture(uStencilTexture, vMaskTexCoord).r;
    vec4 color = texture(uPaintTexture, vColorTexCoord);
    color.a *= coverage;
    color.rgb *= color.a;

    /*
    vec4 destHSLA = convertRGBAToHSLA(texture(uDest, vTexCoord));
    vec4 srcHSLA = convertRGBAToHSLA(color);
    bvec3 blendHSL = equal(uBlendHSL, ivec3(BLEND_TERM_DEST));
    vec4 outputHSLA = vec4(blendHSL.x ? destHSLA.x : srcHSLA.x,
                           blendHSL.y ? destHSLA.y : srcHSLA.y,
                           blendHSL.z ? destHSLA.z : srcHSLA.z,
                           srcHSLA.a + destHSLA.a);
    oFragColor = convertHSLAToRGBA(outputHSLA);*/
    oFragColor = mix(color, vec4(1.0, 0.0, 0.0, 1.0), 0.5);
}
