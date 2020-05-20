// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bMetadata
{
    uint4 iMetadata[1];
};

struct bDrawTiles
{
    uint4 iDrawTiles[1];
};

struct bClipTiles
{
    uint4 iClipTiles[1];
};

struct bClipVertexBuffer
{
    uint iClipVertexBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 16u, 1u);

kernel void main0(const device bMetadata& _31 [[buffer(0)]], device bDrawTiles& _157 [[buffer(1)]], device bClipTiles& _166 [[buffer(2)]], device bClipVertexBuffer& _182 [[buffer(3)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    uint2 tileCoord = uint2(gl_GlobalInvocationID.xy);
    uint pathIndex = gl_WorkGroupID.z;
    uint4 drawTileRect = _31.iMetadata[(pathIndex * 3u) + 0u];
    uint4 clipTileRect = _31.iMetadata[(pathIndex * 3u) + 1u];
    uint4 offsets = _31.iMetadata[(pathIndex * 3u) + 2u];
    uint drawOffset = offsets.x;
    uint clipOffset = offsets.y;
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
        drawTileIndex = int(_157.iDrawTiles[drawTileOffset].y);
        clipTileIndex = int(_166.iClipTiles[clipTileOffset].y);
        clipTileBackdrop = int(_166.iClipTiles[clipTileOffset].w << uint(8)) >> 24;
    }
    _182.iClipVertexBuffer[(drawTileOffset * 3) + 0] = uint(drawTileIndex);
    _182.iClipVertexBuffer[(drawTileOffset * 3) + 1] = uint(clipTileIndex);
    _182.iClipVertexBuffer[(drawTileOffset * 3) + 2] = uint(clipTileBackdrop);
}

