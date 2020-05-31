// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bBackdrops
{
    int iBackdrops[1];
};

struct bDrawMetadata
{
    uint4 iDrawMetadata[1];
};

struct bClipMetadata
{
    uint4 iClipMetadata[1];
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

struct bDestBufferMetadata
{
    int iDestBufferMetadata[1];
};

struct bDestBufferTail
{
    uint4 iDestBufferTail[1];
};

struct bDestBuffer
{
    int iDestBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(64u, 1u, 1u);

static inline __attribute__((always_inline))
uint calculateTileIndex(thread const uint& bufferOffset, thread const uint4& tileRect, thread const uint2& tileCoord)
{
    return (bufferOffset + (tileCoord.y * (tileRect.z - tileRect.x))) + tileCoord.x;
}

kernel void main0(constant int& uColumnCount [[buffer(0)]], constant int2& uFramebufferTileSize [[buffer(7)]], const device bBackdrops& _59 [[buffer(1)]], const device bDrawMetadata& _85 [[buffer(2)]], const device bClipMetadata& _126 [[buffer(3)]], device bDrawTiles& _172 [[buffer(4)]], device bClipTiles& _243 [[buffer(5)]], device bClipVertexBuffer& _299 [[buffer(6)]], device bZBuffer& _357 [[buffer(8)]], device bDestBufferMetadata& _392 [[buffer(9)]], device bDestBufferTail& _399 [[buffer(10)]], device bDestBuffer& _413 [[buffer(11)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint columnIndex = gl_GlobalInvocationID.x;
    if (int(columnIndex) >= uColumnCount)
    {
        return;
    }
    int currentBackdrop = _59.iBackdrops[(columnIndex * 3u) + 0u];
    int tileX = _59.iBackdrops[(columnIndex * 3u) + 1u];
    uint drawPathIndex = uint(_59.iBackdrops[(columnIndex * 3u) + 2u]);
    uint4 drawTileRect = _85.iDrawMetadata[(drawPathIndex * 3u) + 0u];
    uint4 drawOffsets = _85.iDrawMetadata[(drawPathIndex * 3u) + 1u];
    uint2 drawTileSize = drawTileRect.zw - drawTileRect.xy;
    uint drawTileBufferOffset = drawOffsets.x;
    bool zWrite = drawOffsets.z != 0u;
    int clipPathIndex = int(drawOffsets.w);
    uint4 clipTileRect = uint4(0u);
    uint4 clipOffsets = uint4(0u);
    if (clipPathIndex >= 0)
    {
        clipTileRect = _126.iClipMetadata[(clipPathIndex * 2) + 0];
        clipOffsets = _126.iClipMetadata[(clipPathIndex * 2) + 1];
    }
    uint clipTileBufferOffset = clipOffsets.x;
    uint clipBackdropOffset = clipOffsets.y;
    for (uint tileY = 0u; tileY < drawTileSize.y; tileY++)
    {
        uint2 drawTileCoord = uint2(uint(tileX), tileY);
        uint param = drawTileBufferOffset;
        uint4 param_1 = drawTileRect;
        uint2 param_2 = drawTileCoord;
        uint drawTileIndex = calculateTileIndex(param, param_1, param_2);
        int drawAlphaTileIndex = int(_172.iDrawTiles[(drawTileIndex * 4u) + 1u]);
        uint drawTileWord = _172.iDrawTiles[(drawTileIndex * 4u) + 3u];
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
                int clipAlphaTileIndex = int(_243.iClipTiles[(clipTileIndex * 4u) + 1u]);
                uint clipTileWord = _243.iClipTiles[(clipTileIndex * 4u) + 3u];
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
            _299.iClipVertexBuffer[drawTileIndex] = clipTileData;
        }
        _172.iDrawTiles[(drawTileIndex * 4u) + 1u] = uint(drawAlphaTileIndex);
        _172.iDrawTiles[(drawTileIndex * 4u) + 3u] = (drawTileWord & 16777215u) | ((uint(drawTileBackdrop) & 255u) << uint(24));
        if ((zWrite && (drawTileBackdrop != 0)) && (drawAlphaTileIndex < 0))
        {
            int2 tileCoord_1 = int2(tileX, int(tileY)) + int2(drawTileRect.xy);
            int zBufferIndex = (tileCoord_1.y * uFramebufferTileSize.x) + tileCoord_1.x;
            int _362 = atomic_fetch_max_explicit((device atomic_int*)&_357.iZBuffer[zBufferIndex], int(drawPathIndex), memory_order_relaxed);
        }
        if ((drawTileBackdrop != 0) && (drawAlphaTileIndex < 0))
        {
            int2 tileCoord_2 = int2(tileX, int(tileY)) + int2(drawTileRect.xy);
            int destBufferOffset = (tileCoord_2.y * uFramebufferTileSize.x) + tileCoord_2.x;
            int _394 = atomic_fetch_add_explicit((device atomic_int*)&_392.iDestBufferMetadata[0], 1, memory_order_relaxed);
            uint destBufferIndex = uint(_394);
            _399.iDestBufferTail[destBufferIndex].x = 4294967295u;
            _399.iDestBufferTail[destBufferIndex].y = drawPathIndex;
            _399.iDestBufferTail[destBufferIndex].z = drawTileWord;
            int _418 = atomic_exchange_explicit((device atomic_int*)&_413.iDestBuffer[destBufferOffset], int(destBufferIndex), memory_order_relaxed);
            _399.iDestBufferTail[destBufferIndex].w = uint(_418);
        }
        currentBackdrop += delta;
    }
}

