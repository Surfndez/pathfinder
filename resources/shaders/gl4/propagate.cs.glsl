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

layout(std430, binding = 0)buffer bMetadata {
    restrict readonly uvec4 iMetadata[];
};

layout(std430, binding = 1)buffer bAlphaTiles {
    restrict uint iAlphaTiles[];
};

void main(){
    uint metadataOffset = gl_WorkGroupID . y;
    uvec4 metadata = iMetadata[metadataOffset];

    uint tileX = uint(gl_LocalInvocationID . x);

    uvec2 tileSize = metadata . xy;
    uint tileBufferOffset = metadata . z;

    if(tileX >= tileSize . x)
        return;


    int backdrop = 0;
    uint offset = tileBufferOffset;
    for(uint tileY = 0;tileY < tileSize . y;tileY ++){
        uint index =(tileBufferOffset + tileY * tileSize . x + tileX)* 3 + 2;
        uint tileWord = iAlphaTiles[index];
        int delta =(int(tileWord)<< 8)>> 24;
        iAlphaTiles[index]=(tileWord & 0xff00ffff)|((uint(backdrop)& 0xff)<< 16);
        backdrop += delta;
    }
}

