#version 330

// pathfinder/shaders/tile_clip_combine.fs.glsl
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

#define TILE_CLIP_COMBINE_CTRL_ENABLE_0     0x1u
#define TILE_CLIP_COMBINE_CTRL_ENABLE_1     0x2u

uniform sampler2D uSrc;

in vec2 vTexCoord0;
in float vBackdrop0;
in vec2 vTexCoord1;
in float vBackdrop1;
flat in uint vCtrl;

out vec4 oFragColor;

void main() {
    vec4 texColor0 = vec4(0.0), texColor1 = vec4(0.0);
    if ((vCtrl & TILE_CLIP_COMBINE_CTRL_ENABLE_0) != 0u)
        texColor0 = texture(uSrc, vTexCoord0);
    if ((vCtrl & TILE_CLIP_COMBINE_CTRL_ENABLE_1) != 0u)
        texColor1 = texture(uSrc, vTexCoord1);
    oFragColor = min(abs(texColor0 + vBackdrop0), abs(texColor1 + vBackdrop1));
}
