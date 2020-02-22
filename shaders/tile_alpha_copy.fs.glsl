#version 330

// pathfinder/shaders/tile_alpha_copy.fs.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

precision highp float;

uniform vec2 uFramebufferSize;
uniform sampler2D uSrc;

in vec2 vColorTexCoord;
in vec2 vMaskTexCoord;

out vec4 oFragColor;

void main() {
    vec2 texCoord = gl_FragCoord.xy / uFramebufferSize;
#ifndef PF_ORIGIN_UPPER_LEFT
    texCoord.y = 1.0 - texCoord.y;
#endif
    oFragColor = texture(uSrc, texCoord);
}
