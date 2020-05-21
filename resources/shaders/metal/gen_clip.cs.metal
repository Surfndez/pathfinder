// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bClippedPathIndices
{
    uint iClippedPathIndices[1];
};

struct bPropagateMetadata
{
    uint4 iPropagateMetadata[1];
};

struct bTiles
{
    uint4 iTiles[1];
};

struct bClipVertexBuffer
{
    uint iClipVertexBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 16u, 1u);

kernel void main0(const device bClippedPathIndices& _23 [[buffer(0)]], const device bPropagateMetadata& _40 [[buffer(1)]], device bTiles& _174 [[buffer(2)]], device bClipVertexBuffer& _198 [[buffer(3)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    uint2 tileCoord = uint2(gl_GlobalInvocationID.xy);
    uint drawPathIndex = _23.iClippedPathIndices[gl_WorkGroupID.z];
    uint4 drawTileRect = _40.iPropagateMetadata[(drawPathIndex * 2u) + 0u];
    uint4 drawPathMetadata = _40.iPropagateMetadata[(drawPathIndex * 2u) + 1u];
    uint clipPathIndex = drawPathMetadata.w;
    uint4 clipTileRect = _40.iPropagateMetadata[(clipPathIndex * 2u) + 0u];
    uint4 clipPathMetadata = _40.iPropagateMetadata[(clipPathIndex * 2u) + 1u];
    uint drawOffset = drawPathMetadata.x;
    uint clipOffset = clipPathMetadata.x;
    int2 drawTileOffset2D = int2(tileCoord) - int2(drawTileRect.xy);
    int2 clipTileOffset2D = int2(tileCoord) - int2(clipTileRect.xy);
    int drawTilesAcross = int(drawTileRect.z - drawTileRect.x);
    int clipTilesAcross = int(clipTileRect.z - clipTileRect.x);
    int drawTileOffset = drawTileOffset2D.x + (drawTileOffset2D.y * drawTilesAcross);
    int clipTileOffset = clipTileOffset2D.x + (clipTileOffset2D.y * clipTilesAcross);
    bool inBoundsDraw = all(bool4(tileCoord >= drawTileRect.xy, tileCoord < drawTileRect.zw));
    if (!inBoundsDraw)
    {
        return;
    }
    bool inBoundsClip = all(bool4(tileCoord >= clipTileRect.xy, tileCoord < clipTileRect.zw));
    int drawTileIndex = -1;
    int clipTileIndex = -1;
    int clipTileBackdrop = 0;
    if (inBoundsClip)
    {
        uint4 drawTile = _174.iTiles[drawTileOffset];
        uint4 clipTile = _174.iTiles[clipTileOffset];
        drawTileIndex = int(drawTile.y);
        clipTileIndex = int(clipTile.y);
        clipTileBackdrop = int(clipTile.w << uint(8)) >> 24;
    }
    _198.iClipVertexBuffer[(drawTileOffset * 3) + 0] = uint(drawTileIndex);
    _198.iClipVertexBuffer[(drawTileOffset * 3) + 1] = uint(clipTileIndex);
    _198.iClipVertexBuffer[(drawTileOffset * 3) + 2] = uint(clipTileBackdrop);
}

