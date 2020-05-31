// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bFillTileMap
{
    int iFillTileMap[1];
};

struct bFills
{
    uint iFills[1];
};

struct bTiles
{
    int iTiles[1];
};

struct bDestBufferMetadata
{
    uint iDestBufferMetadata[1];
};

struct bDestBufferTail
{
    uint4 iDestBufferTail[1];
};

struct bDestBuffer
{
    uint iDestBuffer[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 4u, 1u);

static inline __attribute__((always_inline))
float4 computeCoverage(thread const float2& from, thread const float2& to, thread const texture2d<float> areaLUT, thread const sampler areaLUTSmplr)
{
    float2 left = select(to, from, bool2(from.x < to.x));
    float2 right = select(from, to, bool2(from.x < to.x));
    float2 window = fast::clamp(float2(from.x, to.x), float2(-0.5), float2(0.5));
    float offset = mix(window.x, window.y, 0.5) - left.x;
    float t = offset / (right.x - left.x);
    float y = mix(left.y, right.y, t);
    float d = (right.y - left.y) / (right.x - left.x);
    float dX = window.x - window.y;
    return areaLUT.sample(areaLUTSmplr, (float2(y + 8.0, abs(d * dX)) / float2(16.0)), level(0.0)) * dX;
}

kernel void main0(constant int2& uTileRange [[buffer(0)]], constant int& uBinnedOnGPU [[buffer(3)]], constant int2& uFramebufferSize [[buffer(5)]], const device bFillTileMap& _164 [[buffer(1)]], const device bFills& _187 [[buffer(2)]], const device bTiles& _269 [[buffer(4)]], device bDestBufferMetadata& _347 [[buffer(6)]], device bDestBufferTail& _353 [[buffer(7)]], device bDestBuffer& _377 [[buffer(8)]], texture2d<float> uAreaLUT [[texture(0)]], sampler uAreaLUTSmplr [[sampler(0)]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    int2 tileSubCoord = int2(gl_LocalInvocationID.xy) * int2(1, 4);
    uint tileIndexOffset = gl_WorkGroupID.x | (gl_WorkGroupID.y << uint(16));
    uint tileIndex = tileIndexOffset + uint(uTileRange.x);
    if (tileIndex >= uint(uTileRange.y))
    {
        return;
    }
    int fillIndex = _164.iFillTileMap[tileIndex];
    if (fillIndex < 0)
    {
        return;
    }
    float4 coverages = float4(0.0);
    int iteration = 0;
    do
    {
        uint fillFrom = _187.iFills[(fillIndex * 3) + 0];
        uint fillTo = _187.iFills[(fillIndex * 3) + 1];
        float4 lineSegment = float4(float(fillFrom & 65535u), float(fillFrom >> uint(16)), float(fillTo & 65535u), float(fillTo >> uint(16))) / float4(256.0);
        float2 param = lineSegment.xy - (float2(tileSubCoord) + float2(0.5));
        float2 param_1 = lineSegment.zw - (float2(tileSubCoord) + float2(0.5));
        coverages += computeCoverage(param, param_1, uAreaLUT, uAreaLUTSmplr);
        fillIndex = int(_187.iFills[(fillIndex * 3) + 2]);
        iteration++;
    } while ((fillIndex >= 0) && (iteration < 1024));
    if (all(coverages == float4(0.0)))
    {
        return;
    }
    uint alphaTileIndex;
    if (uBinnedOnGPU != 0)
    {
        alphaTileIndex = uint(_269.iTiles[(tileIndex * 4u) + 1u]);
    }
    else
    {
        alphaTileIndex = tileIndex;
    }
    int packedTileCoord = _269.iTiles[(tileIndex * 4u) + 0u];
    int2 tileCoord = int2((packedTileCoord << 16) >> 16, packedTileCoord >> 16);
    int2 pixelCoord = (tileCoord * int2(16, 4)) + int2(gl_LocalInvocationID.xy);
    uint destBufferOffset = uint(pixelCoord.x + (pixelCoord.y * uFramebufferSize.x));
    uint4 scaledCoverages = uint4(round(fast::min(abs(coverages), float4(1.0)) * float4(255.0)));
    uint packedCoverages = ((scaledCoverages.x | (scaledCoverages.y << uint(8))) | (scaledCoverages.z << uint(16))) | (scaledCoverages.w << uint(24));
    uint _349 = atomic_fetch_add_explicit((device atomic_uint*)&_347.iDestBufferMetadata[0], 1u, memory_order_relaxed);
    uint tailOffset = _349;
    _353.iDestBufferTail[tailOffset].x = packedCoverages;
    _353.iDestBufferTail[tailOffset].y = uint(_269.iTiles[(tileIndex * 4u) + 2u]);
    _353.iDestBufferTail[tailOffset].z = uint(_269.iTiles[(tileIndex * 4u) + 3u]);
    uint _381 = atomic_exchange_explicit((device atomic_uint*)&_377.iDestBuffer[destBufferOffset], tailOffset, memory_order_relaxed);
    _353.iDestBufferTail[tailOffset].w = _381;
}

