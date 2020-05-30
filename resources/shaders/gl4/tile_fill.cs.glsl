#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












#extension GL_GOOGLE_include_directive : enable

precision highp float;





layout(local_size_x = 16, local_size_y = 4)in;

uniform writeonly image2D uDest;
uniform sampler2D uAreaLUT;
uniform ivec2 uFramebufferTileSize;












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


layout(std430, binding = 0)buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1)buffer bTileLinkMap {
    restrict readonly ivec2 iTileLinkMap[];
};

layout(std430, binding = 2)buffer bTiles {
    restrict readonly int iTiles[];
};

layout(std430, binding = 3)buffer bInitialTileMap {
    restrict readonly uint iInitialTileMap[];
};

bool initFill(inout int tileIndex, inout int fillIndex, uint tileIndexOffset){
    tileIndex = int(iInitialTileMap[tileIndexOffset]);
    while(tileIndex >= 0){
        fillIndex = iTileLinkMap[tileIndex]. x;
        if(fillIndex >= 0)
            return true;
        tileIndex = iTileLinkMap[tileIndex]. y;
    }
    return false;
}

bool nextFill(inout int tileIndex, inout int fillIndex){
    fillIndex = int(iFills[fillIndex * 3 + 2]);
    if(fillIndex >= 0)
        return true;
    tileIndex = iTileLinkMap[tileIndex]. y;

    while(tileIndex >= 0){
        fillIndex = iTileLinkMap[tileIndex]. x;
        if(fillIndex >= 0)
            return true;
        tileIndex = iTileLinkMap[tileIndex]. y;
    }
    return false;
}

void main(){
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID . xy)* ivec2(1, 4);
    ivec2 tileCoord = ivec2(gl_WorkGroupID . xy);

    uint tileIndexOffset = tileCoord . x + tileCoord . y * uFramebufferTileSize . x;
    int tileIndex = - 1, fillIndex = - 1;
    vec4 coverages = vec4(0.0);

    if(initFill(tileIndex, fillIndex, tileIndexOffset)){
        int iteration = 0;
        do {
            uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
            vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                    fillTo & 0xffff, fillTo >> 16)/ 256.0;

            coverages += computeCoverage(lineSegment . xy -(vec2(tileSubCoord)+ vec2(0.5)),
                                        lineSegment . zw -(vec2(tileSubCoord)+ vec2(0.5)),
                                        uAreaLUT);

            iteration ++;
        } while(iteration < 1024 && nextFill(tileIndex, fillIndex));
    }

    ivec2 destCoord = tileCoord * ivec2(16)+ tileSubCoord;
    imageStore(uDest, destCoord + ivec2(0, 0), vec4(coverages . xxx, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 1), vec4(coverages . yyy, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 2), vec4(coverages . zzz, 1.0));
    imageStore(uDest, destCoord + ivec2(0, 3), vec4(coverages . www, 1.0));
}

