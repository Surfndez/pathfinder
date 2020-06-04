// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bTilePathInfo
{
    uint4 iTilePathInfo[1];
};

struct bInitialTileMap
{
    uint iInitialTileMap[1];
};

struct bTileLinkMap
{
    uint2 iTileLinkMap[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(2u, 2u, 1u);

struct bTiles
{
    uint4 iTiles[1];
};

static inline __attribute__((always_inline))
int4 unpackTileRect(thread const uint4& pathInfo)
{
    int2 packedTileRect = int2(pathInfo.xy);
    return int4((packedTileRect.x << 16) >> 16, packedTileRect.x >> 16, (packedTileRect.y << 16) >> 16, packedTileRect.y >> 16);
}

kernel void main0(constant int2& uFramebufferTileSize [[buffer(0)]], constant int& uPathCount [[buffer(1)]], const device bTilePathInfo& _89 [[buffer(2)]], device bInitialTileMap& _144 [[buffer(3)]], device bTileLinkMap& _161 [[buffer(4)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    int2 tileCoords = int2(gl_GlobalInvocationID.xy);
    bool _58 = tileCoords.x >= uFramebufferTileSize.x;
    bool _67;
    if (!_58)
    {
        _67 = tileCoords.y >= uFramebufferTileSize.y;
    }
    else
    {
        _67 = _58;
    }
    if (_67)
    {
        return;
    }
    int prevTileIndex = -1;
    for (uint pathIndex = 0u; pathIndex < uint(uPathCount); pathIndex++)
    {
        uint4 pathInfo = _89.iTilePathInfo[pathIndex];
        uint4 param = pathInfo;
        int4 tileRect = unpackTileRect(param);
        if (all(bool4(tileCoords >= tileRect.xy, tileCoords < tileRect.zw)))
        {
            int tileWidth = tileRect.z - tileRect.x;
            int tileIndex = (int(pathInfo.z) + tileCoords.x) + (tileCoords.y * tileWidth);
            if (prevTileIndex < 0)
            {
                _144.iInitialTileMap[tileCoords.x + (uFramebufferTileSize.x * tileCoords.y)] = uint(tileIndex);
            }
            else
            {
                _161.iTileLinkMap[prevTileIndex].y = uint(tileIndex);
            }
            prevTileIndex = tileIndex;
        }
    }
    if (prevTileIndex < 0)
    {
        _144.iInitialTileMap[tileCoords.x + (uFramebufferTileSize.x * tileCoords.y)] = 4294967295u;
    }
}

