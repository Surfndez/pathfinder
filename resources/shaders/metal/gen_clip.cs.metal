// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bDrawTiles
{
    uint4 iDrawTiles[1];
};

struct bClippedPathIndices
{
    uint iClippedPathIndices[1];
};

struct bDrawPropagateMetadata
{
    uint4 iDrawPropagateMetadata[1];
};

struct bClipPropagateMetadata
{
    uint4 iClipPropagateMetadata[1];
};

struct bClipTiles
{
    uint4 iClipTiles[1];
};

struct bClipVertexBuffer
{
    int4 iClipVertexBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 16u, 1u);

static inline __attribute__((always_inline))
void writeTile(thread const int& tileOffset, thread uint4& originalTile, thread const int& newTileIndex, thread const int& newBackdrop, device bDrawTiles& v_39)
{
    originalTile.y = uint(newTileIndex);
    originalTile.w = (originalTile.w & 4278255615u) | ((uint(newBackdrop) & 255u) << uint(16));
    v_39.iDrawTiles[tileOffset] = originalTile;
}

kernel void main0(device bDrawTiles& v_39 [[buffer(0)]], const device bClippedPathIndices& _60 [[buffer(1)]], const device bDrawPropagateMetadata& _73 [[buffer(2)]], const device bClipPropagateMetadata& _93 [[buffer(3)]], device bClipTiles& _230 [[buffer(4)]], device bClipVertexBuffer& _310 [[buffer(5)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    uint2 tileCoord = uint2(gl_GlobalInvocationID.xy);
    uint drawPathIndex = _60.iClippedPathIndices[gl_WorkGroupID.z];
    uint4 drawTileRect = _73.iDrawPropagateMetadata[(drawPathIndex * 2u) + 0u];
    uint4 drawPathMetadata = _73.iDrawPropagateMetadata[(drawPathIndex * 2u) + 1u];
    uint clipPathIndex = drawPathMetadata.w;
    uint4 clipTileRect = _93.iClipPropagateMetadata[(clipPathIndex * 2u) + 0u];
    uint4 clipPathMetadata = _93.iClipPropagateMetadata[(clipPathIndex * 2u) + 1u];
    int drawOffset = int(drawPathMetadata.x);
    int clipOffset = int(clipPathMetadata.x);
    int2 drawTileOffset2D = int2(tileCoord) - int2(drawTileRect.xy);
    int2 clipTileOffset2D = int2(tileCoord) - int2(clipTileRect.xy);
    int drawTilesAcross = int(drawTileRect.z - drawTileRect.x);
    int clipTilesAcross = int(clipTileRect.z - clipTileRect.x);
    int drawTileOffset = (drawOffset + drawTileOffset2D.x) + (drawTileOffset2D.y * drawTilesAcross);
    int clipTileOffset = (clipOffset + clipTileOffset2D.x) + (clipTileOffset2D.y * clipTilesAcross);
    bool inBoundsDraw = all(bool4(tileCoord >= drawTileRect.xy, tileCoord < drawTileRect.zw));
    if (!inBoundsDraw)
    {
        return;
    }
    bool inBoundsClip = all(bool4(tileCoord >= clipTileRect.xy, tileCoord < clipTileRect.zw));
    uint4 drawTile = v_39.iDrawTiles[drawTileOffset];
    int drawTileIndex = int(drawTile.y);
    int drawTileBackdrop = int(drawTile.w << uint(8)) >> 24;
    int4 clipTileData = int4(-1, 0, -1, 0);
    if (inBoundsClip)
    {
        uint4 clipTile = _230.iClipTiles[clipTileOffset];
        int clipTileIndex = int(clipTile.y);
        int clipTileBackdrop = int(clipTile.w << uint(8)) >> 24;
        if ((clipTileIndex >= 0) && (drawTileIndex >= 0))
        {
            clipTileData = int4(drawTileIndex, drawTileBackdrop, clipTileIndex, clipTileBackdrop);
            int param = drawTileOffset;
            uint4 param_1 = drawTile;
            int param_2 = drawTileIndex;
            int param_3 = 0;
            writeTile(param, param_1, param_2, param_3, v_39);
        }
        else
        {
            if (((clipTileIndex >= 0) && (drawTileIndex < 0)) && (drawTileBackdrop != 0))
            {
                int param_4 = drawTileOffset;
                uint4 param_5 = drawTile;
                int param_6 = clipTileIndex;
                int param_7 = clipTileBackdrop;
                writeTile(param_4, param_5, param_6, param_7, v_39);
            }
            else
            {
                if ((clipTileIndex < 0) && (clipTileBackdrop == 0))
                {
                    int param_8 = drawTileOffset;
                    uint4 param_9 = drawTile;
                    int param_10 = -1;
                    int param_11 = 0;
                    writeTile(param_8, param_9, param_10, param_11, v_39);
                }
            }
        }
    }
    else
    {
        int param_12 = drawTileOffset;
        uint4 param_13 = drawTile;
        int param_14 = -1;
        int param_15 = 0;
        writeTile(param_12, param_13, param_14, param_15, v_39);
    }
    _310.iClipVertexBuffer[drawTileOffset] = clipTileData;
}

