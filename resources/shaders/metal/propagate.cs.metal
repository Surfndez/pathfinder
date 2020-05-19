// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bMetadata
{
    uint4 iMetadata[1];
};

struct bAlphaTiles
{
    uint iAlphaTiles[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(256u, 1u, 1u);

kernel void main0(const device bMetadata& _22 [[buffer(0)]], device bAlphaTiles& _81 [[buffer(1)]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]])
{
    uint metadataOffset = gl_WorkGroupID.y;
    uint4 metadata = _22.iMetadata[metadataOffset];
    uint tileX = gl_LocalInvocationID.x;
    uint2 tileSize = metadata.xy;
    uint tileBufferOffset = metadata.z;
    if (tileX >= tileSize.x)
    {
        return;
    }
    int backdrop = 0;
    uint offset = tileBufferOffset;
    for (uint tileY = 0u; tileY < tileSize.y; tileY++)
    {
        uint index = (((tileBufferOffset + (tileY * tileSize.x)) + tileX) * 3u) + 2u;
        uint tileWord = _81.iAlphaTiles[index];
        int delta = (int(tileWord) << 8) >> 24;
        _81.iAlphaTiles[index] = (tileWord & 4278255615u) | ((uint(backdrop) & 255u) << uint(16));
        backdrop += delta;
    }
}

