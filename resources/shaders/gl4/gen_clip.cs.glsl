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

layout(std430, binding = 1)buffer bPropagateMetadata {
    restrict readonly uvec4 iPropagateMetadata[];
};

layout(std430, binding = 2)buffer bTiles {
    restrict uvec4 iTiles[];
};

layout(std430, binding = 3)buffer bClipVertexBuffer {
    restrict uint iClipVertexBuffer[];
};

void main(){
    uvec2 tileCoord = uvec2(gl_GlobalInvocationID . xy);

    uint drawPathIndex = iClippedPathIndices[gl_WorkGroupID . z];
    uvec4 drawTileRect = iPropagateMetadata[drawPathIndex * 2 + 0];
    uvec4 drawPathMetadata = iPropagateMetadata[drawPathIndex * 2 + 1];

    uint clipPathIndex = drawPathMetadata . w;
    uvec4 clipTileRect = iPropagateMetadata[clipPathIndex * 2 + 0];
    uvec4 clipPathMetadata = iPropagateMetadata[clipPathIndex * 2 + 1];

    uint drawOffset = drawPathMetadata . x, clipOffset = clipPathMetadata . x;
    ivec2 drawTileOffset2D = ivec2(tileCoord)- ivec2(drawTileRect . xy);
    ivec2 clipTileOffset2D = ivec2(tileCoord)- ivec2(clipTileRect . xy);
    int drawTilesAcross = int(drawTileRect . z - drawTileRect . x);
    int clipTilesAcross = int(clipTileRect . z - clipTileRect . x);
    int drawTileOffset = drawTileOffset2D . x + drawTileOffset2D . y * drawTilesAcross;
    int clipTileOffset = clipTileOffset2D . x + clipTileOffset2D . y * clipTilesAcross;

    bool inBoundsDraw = all(bvec4(greaterThanEqual(tileCoord, drawTileRect . xy),
                                  lessThan(tileCoord, drawTileRect . zw)));
    if(! inBoundsDraw)
        return;

    bool inBoundsClip = all(bvec4(greaterThanEqual(tileCoord, clipTileRect . xy),
                                  lessThan(tileCoord, clipTileRect . zw)));

    int drawTileIndex = - 1, clipTileIndex = - 1, clipTileBackdrop = 0;
    if(inBoundsClip){
        uvec4 drawTile = iTiles[drawTileOffset], clipTile = iTiles[clipTileOffset];
        drawTileIndex = int(drawTile . y);
        clipTileIndex = int(clipTile . y);
        clipTileBackdrop = int(clipTile . w << 8)>> 24;


    }

    iClipVertexBuffer[drawTileOffset * 3 + 0]= drawTileIndex;
    iClipVertexBuffer[drawTileOffset * 3 + 1]= clipTileIndex;
    iClipVertexBuffer[drawTileOffset * 3 + 2]= clipTileBackdrop;
}

