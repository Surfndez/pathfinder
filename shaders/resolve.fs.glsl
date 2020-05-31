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
uniform sampler2D uTextureMetadata;
uniform ivec2 uTextureMetadataSize;

layout(std430, binding = 0) buffer bDestBuffer {
    restrict readonly int iDestBuffer[];
};

layout(std430, binding = 1) buffer bDestBufferTail {
    restrict readonly uvec4 iDestBufferTail[];
};

out vec4 oFragColor;

void getMetadata(int color,
                 out vec4 outBaseColor,
                 out vec4 outColorTexMatrix0,
                 out vec4 outColorTexOffsets) {
    vec2 textureMetadataScale = vec2(1.0) / vec2(uTextureMetadataSize);
    vec2 metadataEntryCoord = vec2(color % 128 * 4, color / 128);
    vec2 colorTexMatrix0Coord = (metadataEntryCoord + vec2(0.5, 0.5)) * textureMetadataScale;
    vec2 colorTexOffsetsCoord = (metadataEntryCoord + vec2(1.5, 0.5)) * textureMetadataScale;
    vec2 baseColorCoord = (metadataEntryCoord + vec2(2.5, 0.5)) * textureMetadataScale;
    outColorTexMatrix0 = texture(uTextureMetadata, colorTexMatrix0Coord);
    outColorTexOffsets = texture(uTextureMetadata, colorTexOffsetsCoord);
    outBaseColor = texture(uTextureMetadata, baseColorCoord);
}

void main() {
    ivec2 pixelGroupCoord = ivec2(int(gl_FragCoord.x), int(gl_FragCoord.y) / 4);
    int pixelSubCoord = int(gl_FragCoord.y) % 4;

    int pixelGroupIndex =
        int(iDestBuffer[pixelGroupCoord.x + pixelGroupCoord.y * uFramebufferSize.x]);

    vec4 sortedColors[32];
    uint sortedPathIDs[32];
    int pixelListLength = 0;
    while (pixelListLength < 32 && pixelGroupIndex >= 0) {
        uvec4 pixelRecord = iDestBufferTail[pixelGroupIndex];
        int pathID = int(pixelRecord.y);
        int colorIndex = int(pixelRecord.z & 0xffffu);
        float backdrop = float(int(pixelRecord.z) >> 24);
        float alpha = float((pixelRecord.x >> (pixelSubCoord * 8)) & 0xff) / 255.0 + backdrop;

        vec4 baseColor, colorTexMatrix0, colorTexOffsets;
        getMetadata(colorIndex, baseColor, colorTexMatrix0, colorTexOffsets);

        vec4 color = vec4(baseColor.rgb, baseColor.a * alpha);

        int pixelListIndex = pixelListLength - 1;
        while (pixelListIndex >= 0 && sortedPathIDs[pixelListIndex] < pathID) {
            sortedColors[pixelListIndex + 1] = sortedColors[pixelListIndex];
            sortedPathIDs[pixelListIndex + 1] = sortedPathIDs[pixelListIndex];
            pixelListIndex--;
        }
        sortedColors[pixelListIndex + 1] = color;
        sortedPathIDs[pixelListIndex + 1] = pathID;
        pixelListLength++;

        pixelGroupIndex = int(pixelRecord.w);
    }

    vec4 destColor = vec4(vec3(0.0), 1.0);
    for (int pixelListIndex = pixelListLength - 1; pixelListIndex >= 0; pixelListIndex--) {
        vec4 srcColor = sortedColors[pixelListIndex];
        destColor = mix(destColor, srcColor, srcColor.a);
    }

    oFragColor = destColor;
}
