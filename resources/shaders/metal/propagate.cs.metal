// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bDrawMetadata
{
    uint4 iDrawMetadata[1];
};

struct bClipMetadata
{
    uint4 iClipMetadata[1];
};

struct bBackdrops
{
    int iBackdrops[1];
};

struct bDrawTiles
{
    uint iDrawTiles[1];
};

struct bClipTiles
{
    uint iClipTiles[1];
};

struct bClipVertexBuffer
{
    int4 iClipVertexBuffer[1];
};

struct bZBuffer
{
    int iZBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(256u, 1u, 1u);

static inline __attribute__((always_inline))
uint calculateTileIndex(thread const uint& bufferOffset, thread const uint4& tileRect, thread const uint2& tileCoord)
{
    return (bufferOffset + (tileCoord.y * (tileRect.z - tileRect.x))) + tileCoord.x;
}

kernel void main0(constant int2& uFramebufferTileSize [[buffer(6)]], const device bDrawMetadata& _51 [[buffer(0)]], const device bClipMetadata& _107 [[buffer(1)]], const device bBackdrops& _130 [[buffer(2)]], device bDrawTiles& _163 [[buffer(3)]], device bClipTiles& _234 [[buffer(4)]], device bClipVertexBuffer& _290 [[buffer(5)]], device bZBuffer& _350 [[buffer(7)]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]])
{
    uint drawPathIndex = gl_WorkGroupID.y;
    uint tileX = gl_LocalInvocationID.x;
    uint4 drawTileRect = _51.iDrawMetadata[(drawPathIndex * 2u) + 0u];
    uint4 drawOffsets = _51.iDrawMetadata[(drawPathIndex * 2u) + 1u];
    uint2 drawTileSize = drawTileRect.zw - drawTileRect.xy;
    uint drawTileBufferOffset = drawOffsets.x;
    uint drawBackdropOffset = drawOffsets.y;
    bool zWrite = drawOffsets.z != 0u;
    if (tileX >= drawTileSize.x)
    {
        return;
    }
    int clipPathIndex = int(drawOffsets.w);
    uint4 clipTileRect = uint4(0u);
    uint4 clipOffsets = uint4(0u);
    if (clipPathIndex >= 0)
    {
        clipTileRect = _107.iClipMetadata[(clipPathIndex * 2) + 0];
        clipOffsets = _107.iClipMetadata[(clipPathIndex * 2) + 1];
    }
    uint clipTileBufferOffset = clipOffsets.x;
    uint clipBackdropOffset = clipOffsets.y;
    int currentBackdrop = _130.iBackdrops[drawBackdropOffset + tileX];
    for (uint tileY = 0u; tileY < drawTileSize.y; tileY++)
    {
        uint2 drawTileCoord = uint2(tileX, tileY);
        uint param = drawTileBufferOffset;
        uint4 param_1 = drawTileRect;
        uint2 param_2 = drawTileCoord;
        uint drawTileIndex = calculateTileIndex(param, param_1, param_2);
        int drawAlphaTileIndex = int(_163.iDrawTiles[(drawTileIndex * 4u) + 1u]);
        uint drawTileWord = _163.iDrawTiles[(drawTileIndex * 4u) + 3u];
        int delta = int(drawTileWord) >> 24;
        int drawTileBackdrop = currentBackdrop;
        if (clipPathIndex >= 0)
        {
            uint2 tileCoord = drawTileCoord + drawTileRect.xy;
            int4 clipTileData = int4(-1, 0, -1, 0);
            if (all(bool4(tileCoord >= clipTileRect.xy, tileCoord < clipTileRect.zw)))
            {
                uint2 clipTileCoord = tileCoord - clipTileRect.xy;
                uint param_3 = clipTileBufferOffset;
                uint4 param_4 = clipTileRect;
                uint2 param_5 = clipTileCoord;
                uint clipTileIndex = calculateTileIndex(param_3, param_4, param_5);
                int clipAlphaTileIndex = int(_234.iClipTiles[(clipTileIndex * 4u) + 1u]);
                uint clipTileWord = _234.iClipTiles[(clipTileIndex * 4u) + 3u];
                int clipTileBackdrop = (int(clipTileWord) << 8) >> 24;
                if ((clipAlphaTileIndex >= 0) && (drawAlphaTileIndex >= 0))
                {
                    clipTileData = int4(drawAlphaTileIndex, drawTileBackdrop, clipAlphaTileIndex, clipTileBackdrop);
                    drawTileBackdrop = 0;
                }
                else
                {
                    if (((clipAlphaTileIndex >= 0) && (drawAlphaTileIndex < 0)) && (drawTileBackdrop != 0))
                    {
                        drawAlphaTileIndex = clipAlphaTileIndex;
                        drawTileBackdrop = clipTileBackdrop;
                    }
                    else
                    {
                        if ((clipAlphaTileIndex < 0) && (clipTileBackdrop == 0))
                        {
                            drawAlphaTileIndex = -1;
                            drawTileBackdrop = 0;
                        }
                    }
                }
            }
            else
            {
                drawAlphaTileIndex = -1;
                drawTileBackdrop = 0;
            }
            _290.iClipVertexBuffer[drawTileIndex] = clipTileData;
        }
        _163.iDrawTiles[(drawTileIndex * 4u) + 1u] = uint(drawAlphaTileIndex);
        _163.iDrawTiles[(drawTileIndex * 4u) + 3u] = (drawTileWord & 16777215u) | ((uint(drawTileBackdrop) & 255u) << uint(24));
        if ((zWrite && (drawTileBackdrop != 0)) && (drawAlphaTileIndex < 0))
        {
            int2 tileCoord_1 = int2(int(tileX), int(tileY)) + int2(drawTileRect.xy);
            int zBufferIndex = (tileCoord_1.y * uFramebufferTileSize.x) + tileCoord_1.x;
            int _355 = atomic_fetch_max_explicit((device atomic_int*)&_350.iZBuffer[zBufferIndex], int(drawPathIndex), memory_order_relaxed);
        }
        currentBackdrop += delta;
    }
}

