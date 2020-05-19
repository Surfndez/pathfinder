#version 430

// pathfinder/shaders/blit_buffer.fs.glsl
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

uniform ivec2 uBufferSize;

layout(std430, binding = 0) buffer bBuffer {
    restrict int iBuffer[];
};

in vec2 vTexCoord;

out ivec4 oFragColor;

void main() {
    ivec2 texCoord = ivec2(floor(vTexCoord));
    oFragColor = ivec4(iBuffer[texCoord.y * uBufferSize.x + texCoord.x]);
}
