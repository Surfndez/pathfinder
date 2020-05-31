#version 430

// pathfinder/shaders/resolve.fs.glsl
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

uniform ivec2 uFramebufferSize;

layout(std430, binding = 0) buffer bDestBuffer {
    restrict readonly uvec4 iDestBuffer[];
};

layout(std430, binding = 1) buffer bDestBufferTail {
    restrict readonly uvec4 iDestBufferTail[];
};

out vec4 oFragColor;

void main() {
    ivec2 pixelGroupCoord = ivec2(int(gl_FragCoord.x), int(gl_FragCoord.y) / 4);
    int pixelSubCoord = int(gl_FragCoord.y) % 4;

    int pixelGroupIndex =
        int(iDestBuffer[pixelGroupCoord.x + pixelGroupCoord.y * uFramebufferSize.x]);

    vec4 fragColor = vec4(vec3(0.0), 1.0);
    int iteration = 0;
    while (iteration < 1024 && pixelGroupIndex >= 0) {
        uvec4 pixelRecord = iDestBufferTail[pixelGroupIndex];
        //uint color = //(pixelRecord.x >> (pixelSubCoord * 8)) & 0xff;
        //fragColor += float(color) / 255.0;
        fragColor.rgb += vec3(0.1);
        pixelGroupIndex = int(pixelRecord.w);
        iteration++;
    }

    oFragColor = fragColor;
}
