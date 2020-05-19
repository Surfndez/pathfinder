// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bMetadata
{
    uint4 iMetadata[1];
};

struct bBackdrops
{
    int iBackdrops[1];
};

struct bAlphaTiles
{
    uint iAlphaTiles[1];
};

struct bZBuffer
{
    int iZBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(256u, 1u, 1u);

kernel void main0(constant int2& uFramebufferTileSize [[buffer(3)]], const device bMetadata& _27 [[buffer(0)]], const device bBackdrops& _75 [[buffer(1)]], device bAlphaTiles& _107 [[buffer(2)]], device bZBuffer& _177 [[buffer(4)]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]])
{
    uint pathIndex = gl_WorkGroupID.y;
    uint tileX = gl_LocalInvocationID.x;
    uint4 tileRect = _27.iMetadata[(pathIndex * 2u) + 0u];
    uint4 offsets = _27.iMetadata[(pathIndex * 2u) + 1u];
    uint2 tileSize = tileRect.zw - tileRect.xy;
    uint tileBufferOffset = offsets.x;
    uint backdropOffset = offsets.y;
    bool zWrite = offsets.z != 0u;
    if (tileX >= tileSize.x)
    {
        return;
    }
    int backdrop = _75.iBackdrops[backdropOffset + tileX];
    for (uint tileY = 0u; tileY < tileSize.y; tileY++)
    {
        uint index = ((tileBufferOffset + (tileY * tileSize.x)) + tileX) * 4u;
        uint tileWord = _107.iAlphaTiles[index + 3u];
        int delta = (int(tileWord) << 8) >> 24;
        _107.iAlphaTiles[index + 3u] = (tileWord & 4278255615u) | ((uint(backdrop) & 255u) << uint(16));
        bool _137 = zWrite && (backdrop != 0);
        bool _147;
        if (_137)
        {
            _147 = (_107.iAlphaTiles[index + 1u] & 2147483648u) != 0u;
        }
        else
        {
            _147 = _137;
        }
        if (_147)
        {
            int2 tileCoord = int2(int(tileX), int(tileY)) + int2(tileRect.xy);
            int zBufferIndex = (tileCoord.y * uFramebufferTileSize.x) + tileCoord.x;
            int _182 = atomic_fetch_max_explicit((device atomic_int*)&_177.iZBuffer[zBufferIndex], int(pathIndex), memory_order_relaxed);
        }
        backdrop += delta;
    }
}

