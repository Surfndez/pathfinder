// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bFillRanges
{
    uint iFillRanges[1];
};

struct bFills
{
    uint2 iFills[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 16u, 1u);

struct spvDescriptorSetBuffer0
{
    const device bFillRanges* m_151 [[id(0)]];
    const device bFills* m_183 [[id(1)]];
    texture2d<float> uAreaLUT [[id(2)]];
    sampler uAreaLUTSmplr [[id(3)]];
    texture2d<float, access::write> uDest [[id(4)]];
};

float computeCoverage(thread const float2& from, thread const float2& to, thread const texture2d<float> areaLUT, thread const sampler areaLUTSmplr)
{
    float2 left = select(to, from, bool2(from.x < to.x));
    float2 right = select(from, to, bool2(from.x < to.x));
    float2 window = fast::clamp(float2(from.x, to.x), float2(-0.5), float2(0.5));
    float offset = mix(window.x, window.y, 0.5) - left.x;
    float t = offset / (right.x - left.x);
    float y = mix(left.y, right.y, t);
    float d = (right.y - left.y) / (right.x - left.x);
    float dX = window.x - window.y;
    return areaLUT.sample(areaLUTSmplr, (float2(y + 8.0, abs(d * dX)) / float2(16.0)), level(0.0)).x * dX;
}

kernel void main0(constant spvDescriptorSetBuffer0& spvDescriptorSet0 [[buffer(0)]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    int2 tileSubCoord = int2(gl_WorkGroupID.xy);
    uint tileIndex = gl_WorkGroupID.z;
    int2 tileOrigin = int2(int(tileIndex & 255u), int(tileIndex >> 8u)) * int2(16);
    uint startFillIndex = (*spvDescriptorSet0.m_151).iFillRanges[tileIndex];
    uint endFillIndex = (*spvDescriptorSet0.m_151).iFillRanges[tileIndex + 1u];
    if (startFillIndex < endFillIndex)
    {
        float coverage = 0.0;
        for (uint fillIndex = startFillIndex; fillIndex < endFillIndex; fillIndex++)
        {
            uint2 fill = (*spvDescriptorSet0.m_183).iFills[fillIndex];
            float2 from = float2(float(fill.y & 15u), float((fill.y >> 4u) & 15u)) + (float2(float(fill.x & 255u), float((fill.x >> 8u) & 255u)) / float2(256.0));
            float2 to = float2(float((fill.y >> 8u) & 15u), float((fill.y >> 16u) & 15u)) + (float2(float((fill.x >> 16u) & 255u), float((fill.x >> 24u) & 255u)) / float2(256.0));
            from -= float2(tileSubCoord);
            to -= float2(tileSubCoord);
            float2 param = from;
            float2 param_1 = to;
            coverage += computeCoverage(param, param_1, spvDescriptorSet0.uAreaLUT, spvDescriptorSet0.uAreaLUTSmplr);
        }
        spvDescriptorSet0.uDest.write(float4(coverage), uint2((tileOrigin + tileSubCoord)));
    }
}

