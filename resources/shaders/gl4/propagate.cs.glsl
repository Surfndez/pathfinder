#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!














#extension GL_GOOGLE_include_directive : enable

precision highp float;
















vec4 computeCoverage(vec2 from, vec2 to, sampler2D areaLUT){

    vec2 left = from . x < to . x ? from : to, right = from . x < to . x ? to : from;


    vec2 window = clamp(vec2(from . x, to . x), - 0.5, 0.5);
    float offset = mix(window . x, window . y, 0.5)- left . x;
    float t = offset /(right . x - left . x);


    float y = mix(left . y, right . y, t);
    float d =(right . y - left . y)/(right . x - left . x);


    float dX = window . x - window . y;
    return texture(areaLUT, vec2(y + 8.0, abs(d * dX))/ 16.0)* dX;
}



layout(local_size_x = 256)in;

uniform ivec2 uFramebufferTileSize;

layout(std430, binding = 0)buffer bMetadata {
    restrict readonly uvec4 iMetadata[];
};

layout(std430, binding = 1)buffer bBackdrops {
    restrict readonly int iBackdrops[];
};

layout(std430, binding = 2)buffer bAlphaTiles {
    restrict uint iAlphaTiles[];
};

layout(std430, binding = 3)buffer bZBuffer {
    restrict int iZBuffer[];
};

void main(){
    uint pathIndex = gl_WorkGroupID . y;
    uint tileX = uint(gl_LocalInvocationID . x);

    uvec4 tileRect = iMetadata[pathIndex * 2 + 0];
    uvec4 offsets = iMetadata[pathIndex * 2 + 1];
    uvec2 tileSize = tileRect . zw - tileRect . xy;
    uint tileBufferOffset = offsets . x, backdropOffset = offsets . y;
    bool zWrite = offsets . z != 0;

    if(tileX >= tileSize . x)
        return;

    int backdrop = iBackdrops[backdropOffset + tileX];
    for(uint tileY = 0;tileY < tileSize . y;tileY ++){
        uint index =(tileBufferOffset + tileY * tileSize . x + tileX)* 4;
        uint tileWord = iAlphaTiles[index + 3];
        int delta =(int(tileWord)<< 8)>> 24;
        iAlphaTiles[index + 3]=(tileWord & 0xff00ffff)|((uint(backdrop)& 0xff)<< 16);


        if(zWrite && backdrop != 0 &&(iAlphaTiles[index + 1]& 0x80000000)!= 0){
            ivec2 tileCoord = ivec2(tileX, tileY)+ ivec2(tileRect . xy);
            int zBufferIndex = tileCoord . y * uFramebufferTileSize . x + tileCoord . x;
            atomicMax(iZBuffer[zBufferIndex], int(pathIndex));
        }

        backdrop += delta;
    }
}

