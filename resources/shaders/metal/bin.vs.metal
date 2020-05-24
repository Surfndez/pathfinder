// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float2 vFrom [[user(locn0)]];
    float2 vTo [[user(locn1)]];
    uint vPathIndex [[user(locn2)]];
    float4 gl_Position [[position]];
};

struct main0_in
{
    int2 aTessCoord [[attribute(0)]];
    float2 aFrom [[attribute(1)]];
    float2 aTo [[attribute(2)]];
    int aPathIndex [[attribute(3)]];
};

vertex main0_out main0(main0_in in [[stage_in]], constant int2& uFramebufferSize [[buffer(0)]])
{
    main0_out out = {};
    float2 vector = normalize(in.aTo - in.aFrom);
    float2 normal = float2(-vector.y, vector.x);
    float2 tessCoord = float2(in.aTessCoord);
    float2 tilePosition = mix((in.aFrom / float2(16.0)) - vector, (in.aTo / float2(16.0)) + vector, float2(tessCoord.y)) + mix(-normal, normal, float2(tessCoord.x));
    out.vFrom = in.aFrom / float2(16.0);
    out.vTo = in.aTo / float2(16.0);
    out.vPathIndex = uint(in.aPathIndex);
    out.gl_Position = float4(mix(float2(-1.0), float2(1.0), tilePosition / float2(uFramebufferSize)), 0.0, 1.0);
    return out;
}

