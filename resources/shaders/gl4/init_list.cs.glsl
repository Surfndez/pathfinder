#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!














#extension GL_GOOGLE_include_directive : enable

precision highp float;





layout(local_size_x = 2, local_size_y = 2)in;

uniform ivec2 uFramebufferTileSize;
uniform int uPathCount;

layout(std430, binding = 0)buffer bTilePathInfo {




    restrict readonly uvec4 iTilePathInfo[];
};

layout(std430, binding = 1)buffer bTiles {




    restrict readonly uvec4 iTiles[];
};

layout(std430, binding = 2)buffer bTileLinkMap {
    restrict uvec2 iTileLinkMap[];
};

layout(std430, binding = 3)buffer bInitialTileMap {
    restrict uint iInitialTileMap[];
};

ivec4 unpackTileRect(uvec4 pathInfo){
    ivec2 packedTileRect = ivec2(pathInfo . xy);
    return ivec4((packedTileRect . x << 16)>> 16, packedTileRect . x >> 16,
                 (packedTileRect . y << 16)>> 16, packedTileRect . y >> 16);
}

void main(){
    ivec2 tileCoords = ivec2(gl_GlobalInvocationID . xy);
    if(tileCoords . x >= uFramebufferTileSize . x || tileCoords . y >= uFramebufferTileSize . y)
        return;

    int prevTileIndex = - 1;
    for(uint pathIndex = 0;pathIndex < uint(uPathCount);pathIndex ++){
        uvec4 pathInfo = iTilePathInfo[pathIndex];
        ivec4 tileRect = unpackTileRect(pathInfo);
        if(all(bvec4(greaterThanEqual(tileCoords, tileRect . xy),
                      lessThan(tileCoords, tileRect . zw)))){
            int tileWidth = tileRect . z - tileRect . x;
            int tileIndex = int(pathInfo . z)+ tileCoords . x + tileCoords . y * tileWidth;
            if(prevTileIndex < 0)
                iInitialTileMap[tileCoords . x + uFramebufferTileSize . x * tileCoords . y]= tileIndex;
            else
                iTileLinkMap[prevTileIndex]. y = tileIndex;
            prevTileIndex = tileIndex;
        }
    }

    if(prevTileIndex < 0)
        iInitialTileMap[tileCoords . x + uFramebufferTileSize . x * tileCoords . y]= - 1;
}

