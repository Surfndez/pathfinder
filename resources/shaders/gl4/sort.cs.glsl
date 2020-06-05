#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!














#extension GL_GOOGLE_include_directive : enable

precision highp float;





layout(local_size_x = 16, local_size_y = 16)in;

uniform ivec2 uFramebufferTileSize;
uniform int uPathCount;

layout(std430, binding = 0)buffer bTileLinkMap {
    restrict uvec2 iTileLinkMap[];
};

layout(std430, binding = 1)buffer bInitialTileMap {
    restrict uint iInitialTileMap[];
};

void sortedInsert(inout uint headIndex, uint newNodeIndex){
    if(headIndex == ~ 0 || headIndex >= newNodeIndex){
        iTileLinkMap[newNodeIndex]. y = headIndex;
        headIndex = newNodeIndex;
        return;
    }

    uint currentNodeIndex = headIndex;
    while(iTileLinkMap[currentNodeIndex]. y != ~ 0 &&
           iTileLinkMap[currentNodeIndex]. y < newNodeIndex){
        currentNodeIndex = iTileLinkMap[currentNodeIndex]. y;
    }
    iTileLinkMap[newNodeIndex]. y = iTileLinkMap[currentNodeIndex]. y;
    iTileLinkMap[currentNodeIndex]. y = newNodeIndex;
}

void insertionSort(inout uint headIndex){
    uint sortedHeadIndex = ~ 0;

    uint currentNodeIndex = headIndex;
    while(currentNodeIndex != ~ 0){
        uint nextNodeIndex = iTileLinkMap[currentNodeIndex]. y;
        sortedInsert(sortedHeadIndex, currentNodeIndex);
        currentNodeIndex = nextNodeIndex;
    }

    headIndex = sortedHeadIndex;
}

void main(){
    ivec2 tileCoords = ivec2(gl_GlobalInvocationID . xy);
    if(tileCoords . x >= uFramebufferTileSize . x || tileCoords . y >= uFramebufferTileSize . y)
        return;

    uint tileMapIndex = tileCoords . x + tileCoords . y * uFramebufferTileSize . x;
    uint headIndex = iInitialTileMap[tileMapIndex];
    insertionSort(headIndex);
    iInitialTileMap[tileMapIndex]= headIndex;
}

