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


layout(local_size_x = 16, local_size_y = 4)in;


uniform ivec2 uFramebufferSize;
uniform sampler2D uAreaLUT;
uniform ivec2 uTileRange;
uniform int uBinnedOnGPU;

layout(std430, binding = 0)buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1)buffer bFillTileMap {
    restrict readonly int iFillTileMap[];
};

layout(std430, binding = 2)buffer bTiles {




    restrict readonly int iTiles[];
};

layout(std430, binding = 3)buffer bDestBufferMetadata {
    restrict uint iDestBufferMetadata[];
};

layout(std430, binding = 4)buffer bDestBuffer {
    restrict uint iDestBuffer[];
};

layout(std430, binding = 5)buffer bDestBufferTail {
    restrict uvec4 iDestBufferTail[];
};

void main(){
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID . xy)* ivec2(1, 4);


    uint tileIndexOffset = gl_WorkGroupID . x |(gl_WorkGroupID . y << 16);
    uint tileIndex = tileIndexOffset + uint(uTileRange . x);
    if(tileIndex >= uTileRange . y)
        return;

    int fillIndex = iFillTileMap[tileIndex];
    if(fillIndex < 0)
        return;

    vec4 coverages = vec4(0.0);
    int iteration = 0;
    do {
        uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
        vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                fillTo & 0xffff, fillTo >> 16)/ 256.0;

        coverages += computeCoverage(lineSegment . xy -(vec2(tileSubCoord)+ vec2(0.5)),
                                     lineSegment . zw -(vec2(tileSubCoord)+ vec2(0.5)),
                                     uAreaLUT);

        fillIndex = int(iFills[fillIndex * 3 + 2]);
        iteration ++;
    } while(fillIndex >= 0 && iteration < 1024);


    if(all(equal(coverages, vec4(0.0))))
        return;







    uint alphaTileIndex;
    if(uBinnedOnGPU != 0)
        alphaTileIndex = iTiles[tileIndex * 4 + 1];
    else
        alphaTileIndex = tileIndex;

    int packedTileCoord = int(iTiles[tileIndex * 4 + 0]);
    ivec2 tileCoord = ivec2((packedTileCoord << 16)>> 16, packedTileCoord >> 16);
    ivec2 pixelCoord = tileCoord * ivec2(16, 4)+ ivec2(gl_LocalInvocationID . xy);
    uint destBufferOffset = pixelCoord . x + pixelCoord . y * uFramebufferSize . x;

    uint tailOffset = atomicAdd(iDestBufferMetadata[0], 1);
    iDestBufferTail[tailOffset]. x = uint(coverages . x);
    iDestBufferTail[tailOffset]. y = iTiles[tileIndex * 4 + 2];
    iDestBufferTail[tailOffset]. w = atomicExchange(iDestBuffer[destBufferOffset], tailOffset);








}

