#version 330

// pathfinder/demo3/shaders/post.fs.glsl
//
// Copyright © 2019 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

// TODO(pcwalton): This could be significantly optimized by operating on a
// sparse per-tile basis.

precision highp float;

uniform sampler2D uSource;
uniform sampler2D uGammaLUT;
uniform vec2 uFramebufferSize;
uniform vec4 uKernel;
uniform vec4 uBGColor;

in vec2 vTexCoord;

out vec4 oFragColor;

float gammaCorrectChannel(float fgColor) {
    return texture(uGammaLUT, vec2(fgColor, 1.0 - uBGColor)).r;
}

// `fgColor` is in linear space.
vec3 gammaCorrect(vec3 fgColor) {
    return vec3(gammaCorrectChannel(fgColor.r),
                gammaCorrectChannel(fgColor.g),
                gammaCorrectChannel(fgColor.b));
}

float sample1Tap(float offset) {
    return texture(uSource, vec2(vTexCoord.x + offset, vTexCoord.y)).r;
}

void sample9Tap(out vec4 outAlphaLeft,
                out float outAlphaCenter,
                out vec4 outAlphaRight,
                float onePixel) {
    outAlphaLeft   = vec4(uKernel.x > 0.0 ? sample1Tap(-4.0 * onePixel) : 0.0,
                          sample1Tap(-3.0 * onePixel),
                          sample1Tap(-2.0 * onePixel),
                          sample1Tap(-1.0 * onePixel));
    outAlphaCenter = sample1Tap(0.0);
    outAlphaRight  = vec4(sample1Tap(1.0 * onePixel),
                          sample1Tap(2.0 * onePixel),
                          sample1Tap(3.0 * onePixel),
                          uKernel.x > 0.0 ? sample1Tap(4.0 * onePixel) : 0.0);
}

float convolve7Tap(vec4 alpha0, vec3 alpha1) {
    return dot(alpha0, uKernel) + dot(alpha1, uKernel.zyx);
}

void main() {
    // Apply defringing if necessary.
    vec3 fgColor;
    if (uKernel.w == 0.0) {
        fgColor = texture(uSource, vTexCoord).rgb;
    } else {
        vec4 alphaLeft, alphaRight;
        float alphaCenter;
        sample9Tap(alphaLeft, alphaCenter, alphaRight, 1.0 / uFramebufferSize.x);

        fgColor =
            vec3(convolve7Tap(alphaLeft, vec3(alphaCenter, alphaRight.xy)),
                 convolve7Tap(vec4(alphaLeft.yzw, alphaCenter), alphaRight.xyz),
                 convolve7Tap(vec4(alphaLeft.zw, alphaCenter, alphaRight.x), alphaRight.yzw));
    }

    // Apply gamma correction if necessary.
    if (uBGColor.a > 0.0)
        fgColor = gammaCorrect(fgColor);

    // Finish.
    oFragColor = vec4(fgColor, 1.0);
}