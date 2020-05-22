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



layout(local_size_x = 16, local_size_y = 16)in;

layout(std430, binding = 0)buffer bClippedPathIndices {
    restrict readonly uint iClippedPathIndices[];
};

layout(std430, binding = 1)buffer bDrawPropagateMetadata {
    restrict readonly uvec4 iDrawPropagateMetadata[];
};

layout(std430, binding = 2)buffer bClipPropagateMetadata {
    restrict readonly uvec4 iClipPropagateMetadata[];
};

layout(std430, binding = 3)buffer bDrawTiles {
    restrict uvec4 iDrawTiles[];
};

layout(std430, binding = 4)buffer bClipTiles {
    restrict uvec4 iClipTiles[];
};

layout(std430, binding = 5)buffer bClipVertexBuffer {
    restrict ivec4 iClipVertexBuffer[];
};

void writeTile(int tileOffset, uvec4 originalTile, int newTileIndex, int newBackdrop){
    originalTile . y = uint(newTileIndex);
    originalTile . w = uint(originalTile . w & 0xff00ffff)|((uint(newBackdrop)& 0xff)<< 16);
    iDrawTiles[tileOffset]= originalTile;
}

void main(){
    uvec2 tileCoord = uvec2(gl_GlobalInvocationID . xy);

    uint drawPathIndex = iClippedPathIndices[gl_WorkGroupID . z];
    uvec4 drawTileRect = iDrawPropagateMetadata[drawPathIndex * 2 + 0];
    uvec4 drawPathMetadata = iDrawPropagateMetadata[drawPathIndex * 2 + 1];

    uint clipPathIndex = drawPathMetadata . w;
    uvec4 clipTileRect = iClipPropagateMetadata[clipPathIndex * 2 + 0];
    uvec4 clipPathMetadata = iClipPropagateMetadata[clipPathIndex * 2 + 1];

    int drawOffset = int(drawPathMetadata . x), clipOffset = int(clipPathMetadata . x);
    ivec2 drawTileOffset2D = ivec2(tileCoord)- ivec2(drawTileRect . xy);
    ivec2 clipTileOffset2D = ivec2(tileCoord)- ivec2(clipTileRect . xy);
    int drawTilesAcross = int(drawTileRect . z - drawTileRect . x);
    int clipTilesAcross = int(clipTileRect . z - clipTileRect . x);
    int drawTileOffset = drawOffset + drawTileOffset2D . x + drawTileOffset2D . y * drawTilesAcross;
    int clipTileOffset = clipOffset + clipTileOffset2D . x + clipTileOffset2D . y * clipTilesAcross;

    bool inBoundsDraw = all(bvec4(greaterThanEqual(tileCoord, drawTileRect . xy),
                                  lessThan(tileCoord, drawTileRect . zw)));
    if(! inBoundsDraw)
        return;

    bool inBoundsClip = all(bvec4(greaterThanEqual(tileCoord, clipTileRect . xy),
                                  lessThan(tileCoord, clipTileRect . zw)));

    uvec4 drawTile = iDrawTiles[drawTileOffset];
    int drawTileIndex = int(drawTile . y), drawTileBackdrop = int(drawTile . w << 8)>> 24;

    ivec4 clipTileData = ivec4(- 1, 0, - 1, 0);
    if(inBoundsClip){
        uvec4 clipTile = iClipTiles[clipTileOffset];
        int clipTileIndex = int(clipTile . y), clipTileBackdrop = int(clipTile . w << 8)>> 24;


        if(clipTileIndex >= 0 && drawTileIndex >= 0){



            clipTileData = ivec4(drawTileIndex, drawTileBackdrop, clipTileIndex, clipTileBackdrop);
            writeTile(drawTileOffset, drawTile, drawTileIndex, 0);
        } else if(clipTileIndex >= 0 && drawTileIndex < 0 && drawTileBackdrop != 0){


            writeTile(drawTileOffset, drawTile, clipTileIndex, clipTileBackdrop);
        } else if(clipTileIndex < 0 && clipTileBackdrop == 0){

            writeTile(drawTileOffset, drawTile, - 1, 0);
        }
    } else {

        writeTile(drawTileOffset, drawTile, - 1, 0);
    }

    iClipVertexBuffer[drawTileOffset]= clipTileData;
}

