#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;





uniform vec2 uFramebufferSize;
uniform vec2 uTileSize;

in uvec2 aTessCoord;
in uvec4 aLineSegment;
in int aTileIndex;

out vec2 vFrom;
out vec2 vTo;

vec2 computeTileOffset(uint tileIndex, float stencilTextureWidth){
    uint tilesPerRow = uint(stencilTextureWidth / uTileSize . x);
    uvec2 tileOffset = uvec2(tileIndex % tilesPerRow, tileIndex / tilesPerRow);
    return vec2(tileOffset)* uTileSize * vec2(1.0, 0.25);
}

void main(){
    vec2 tileOrigin = computeTileOffset(uint(aTileIndex), uFramebufferSize . x);

    vec4 lineSegment = vec4(aLineSegment)/ 256.0;
    vec2 from = lineSegment . xy, to = lineSegment . zw;

    vec2 position;
    if(aTessCoord . x == 0u)
        position . x = floor(min(from . x, to . x));
    else
        position . x = ceil(max(from . x, to . x));
    if(aTessCoord . y == 0u)
        position . y = floor(min(from . y, to . y));
    else
        position . y = uTileSize . y;
    position . y = floor(position . y * 0.25);





    vec2 offset = vec2(0.0, 1.5)- position * vec2(1.0, 4.0);
    vFrom = from + offset;
    vTo = to + offset;

    vec2 globalPosition =(tileOrigin + position)/ uFramebufferSize * 2.0 - 1.0;



    gl_Position = vec4(globalPosition, 0.0, 1.0);
}

