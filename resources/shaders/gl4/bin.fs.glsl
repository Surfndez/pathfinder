#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;





layout(std430, binding = 0)buffer bPathTileInfo {
    restrict readonly ivec4 iPathTileInfo[];
};

layout(std430, binding = 1)buffer bMetadata {
    restrict uint iMetadata[];
};

layout(std430, binding = 2)buffer bFills {
    restrict writeonly ivec4 iFills[];
};

layout(std430, binding = 3)buffer bAlphaTiles {
    restrict ivec4 iAlphaTiles[];
};

layout(std430, binding = 4)buffer bAlphaTileMap {
    restrict uint iAlphaTileMap[];
};

in vec2 vFrom;
in vec2 vTo;
flat in uint vPath;

out vec4 oFragColor;

void main(){
    ivec2 tileCoord = ivec2(gl_FragCoord . xy);
    ivec4 pathTileRect = iPathTileInfo[vPath * 2 + 0];
    uint pathTileStartIndex = uint(iPathTileInfo[vPath * 2 + 1]. x);
    ivec2 tileOffset = tileCoord - pathTileRect . xy;
    int pathTileRectWidth = pathTileRect . z - pathTileRect . x;
    uint tileIndex = uint(tileOffset . y * pathTileRectWidth + tileOffset . x);
    uint globalTileIndex = pathTileStartIndex + tileIndex;


    uint tileFillIndex = atomicAdd(iAlphaTileMap[globalTileIndex], 1);
    if(tileFillIndex == 0){
        uint alphaTileIndex = atomicAdd(iMetadata[1], 1);
        iAlphaTiles[alphaTileIndex]= ivec4(tileCoord, int(vPath), 0);
    }

    uint fillIndex = atomicAdd(iMetadata[0], 1);
    iFills[fillIndex * 2 + 0]= ivec4(vFrom, vTo);
    iFills[fillIndex * 2 + 1]= ivec4(tileCoord, int(vPath), 0);

    oFragColor = vec4(1.0, 0.0, 0.0, 1.0);
}

