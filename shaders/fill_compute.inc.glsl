// pathfinder/shaders/fill_compute.inc.glsl
//
// Copyright © 2020 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

vec4 computeCoverage(vec2 from, vec2 to, sampler2D areaLUT);

ivec2 calculateTileOrigin(uint tileIndex) {
    return ivec2(tileIndex & 0xff, (tileIndex >> 8u) & 0xff) * 16;
}

vec4 calculateFillAlpha(ivec2 tileSubCoord, uint tileIndex) {
    int fillIndex = iFillTileMap[tileIndex];
    if (fillIndex < 0)
        return vec4(0.0);

    vec4 coverages = vec4(0.0);
    do {
        uvec2 fill = iFills[fillIndex];
        vec2 from = vec2(fill.y & 0xf,           (fill.y >> 4u) & 0xf) +
                    vec2(fill.x & 0xff,          (fill.x >> 8u) & 0xff) / 256.0;
        vec2 to   = vec2((fill.y >> 8u) & 0xf,   (fill.y >> 12u) & 0xf) +
                    vec2((fill.x >> 16u) & 0xff, (fill.x >> 24u) & 0xff) / 256.0;

        coverages += computeCoverage(from - (vec2(tileSubCoord) + vec2(0.5)),
                                     to   - (vec2(tileSubCoord) + vec2(0.5)),
                                     uAreaLUT);

        fillIndex = iNextFills[fillIndex];
    } while (fillIndex >= 0);

    return coverages;
}
