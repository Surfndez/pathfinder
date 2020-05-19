// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

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

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(256u, 1u, 1u);

kernel void main0(const device bMetadata& _27 [[buffer(0)]], const device bBackdrops& _60 [[buffer(1)]], device bAlphaTiles& _92 [[buffer(2)]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]])
{
    uint metadataOffset = gl_WorkGroupID.y;
    uint tileX = gl_LocalInvocationID.x;
    uint4 metadata = _27.iMetadata[metadataOffset];
    uint2 tileSize = metadata.xy;
    uint tileBufferOffset = metadata.z;
    uint backdropOffset = metadata.w;
    if (tileX >= tileSize.x)
    {
        return;
    }
    int backdrop = _60.iBackdrops[backdropOffset + tileX];
    for (uint tileY = 0u; tileY < tileSize.y; tileY++)
    {
        uint index = (((tileBufferOffset + (tileY * tileSize.x)) + tileX) * 3u) + 2u;
        uint tileWord = _92.iAlphaTiles[index];
        int delta = (int(tileWord) << 8) >> 24;
        _92.iAlphaTiles[index] = (tileWord & 4278255615u) | ((uint(backdrop) & 255u) << uint(16));
        backdrop += delta;
    }
}

