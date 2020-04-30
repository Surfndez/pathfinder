// pathfinder/shaders/tile_vertex.inc.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

void lookupTextureMetadata(int color,
                           out mat2 outColorTexMatrix0,
                           out vec4 outColorTexOffsets,
                           out vec4 outBaseColor) {
    vec2 textureMetadataScale = vec2(1.0) / vec2(uTextureMetadataSize);
    vec2 metadataEntryCoord = vec2(color % 128 * 4, color / 128);
    vec2 colorTexMatrix0Coord = (metadataEntryCoord + vec2(0.5, 0.5)) * textureMetadataScale;
    vec2 colorTexOffsetsCoord = (metadataEntryCoord + vec2(1.5, 0.5)) * textureMetadataScale;
    vec2 baseColorCoord = (metadataEntryCoord + vec2(2.5, 0.5)) * textureMetadataScale;
    outColorTexMatrix0 = mat2(texture(uTextureMetadata, colorTexMatrix0Coord));
    outColorTexOffsets = texture(uTextureMetadata, colorTexOffsetsCoord);
    outBaseColor = texture(uTextureMetadata, baseColorCoord);
}
