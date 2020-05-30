// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bTilePathInfo
{
    uint4 iTilePathInfo[1];
};

struct bTiles
{
    uint4 iTiles[1];
};

struct bTileLinkMap
{
    uint2 iTileLinkMap[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(64u, 1u, 1u);

static inline __attribute__((always_inline))
int4 unpackTileRect(thread const uint4& pathInfo)
{
    int2 packedTileRect = int2(pathInfo.xy);
    return int4((packedTileRect.x << 16) >> 16, packedTileRect.x >> 16, (packedTileRect.y << 16) >> 16, packedTileRect.y >> 16);
}

kernel void main0(constant int& uTileCount [[buffer(0)]], constant int& uPathCount [[buffer(1)]], const device bTilePathInfo& _99 [[buffer(2)]], device bTiles& _161 [[buffer(3)]], device bTileLinkMap& _183 [[buffer(4)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint tileCount = uint(uTileCount);
    uint pathCount = uint(uPathCount);
    uint tileIndex = gl_GlobalInvocationID.x;
    if (tileIndex >= tileCount)
    {
        return;
    }
    uint lowPathIndex = 0u;
    uint highPathIndex = pathCount;
    int iteration = 0;
    for (;;)
    {
        bool _79 = iteration < 1024;
        bool _86;
        if (_79)
        {
            _86 = (lowPathIndex + 1u) < highPathIndex;
        }
        else
        {
            _86 = _79;
        }
        if (_86)
        {
            uint midPathIndex = lowPathIndex + ((highPathIndex - lowPathIndex) / 2u);
            uint midTileIndex = _99.iTilePathInfo[midPathIndex].z;
            if (tileIndex < midTileIndex)
            {
                highPathIndex = midPathIndex;
            }
            else
            {
                lowPathIndex = midPathIndex;
                if (tileIndex == midTileIndex)
                {
                    break;
                }
            }
            iteration++;
            continue;
        }
        else
        {
            break;
        }
    }
    uint pathIndex = lowPathIndex;
    uint4 pathInfo = _99.iTilePathInfo[pathIndex];
    uint4 param = pathInfo;
    int4 tileRect = unpackTileRect(param);
    uint tileOffset = tileIndex - pathInfo.z;
    uint tileWidth = uint(tileRect.z - tileRect.x);
    int2 tileCoords = tileRect.xy + int2(int(tileOffset % tileWidth), int(tileOffset / tileWidth));
    _161.iTiles[tileIndex] = uint4((uint(tileCoords.x) & 65535u) | (uint(tileCoords.y) << uint(16)), 4294967295u, pathIndex, pathInfo.w);
    _183.iTileLinkMap[tileIndex] = uint2(4294967295u);
}

