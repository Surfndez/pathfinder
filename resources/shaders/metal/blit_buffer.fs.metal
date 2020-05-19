// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bBuffer
{
    int iBuffer[1];
};

struct main0_out
{
    int4 oFragColor [[color(0)]];
};

struct main0_in
{
    float2 vTexCoord [[user(locn0)]];
};

fragment main0_out main0(main0_in in [[stage_in]], constant int2& uBufferSize [[buffer(1)]], device bBuffer& _23 [[buffer(0)]])
{
    main0_out out = {};
    int2 texCoord = int2(floor(in.vTexCoord));
    out.oFragColor = int4(_23.iBuffer[(texCoord.y * uBufferSize.x) + texCoord.x]);
    return out;
}

