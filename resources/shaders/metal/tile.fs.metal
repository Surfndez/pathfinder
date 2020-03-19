// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct spvDescriptorSetBuffer0
{
    constant int* uCtrl [[id(0)]];
    texture2d<float> uMaskTexture0 [[id(1)]];
    sampler uMaskTexture0Smplr [[id(2)]];
    texture2d<float> uMaskTexture1 [[id(3)]];
    sampler uMaskTexture1Smplr [[id(4)]];
    texture2d<float> uColorTexture0 [[id(5)]];
    sampler uColorTexture0Smplr [[id(6)]];
    constant float4* uFilterParams0 [[id(7)]];
    constant float4* uFilterParams1 [[id(8)]];
    texture2d<float> uColorTexture1 [[id(9)]];
    sampler uColorTexture1Smplr [[id(10)]];
    texture2d<float> uDestTexture [[id(11)]];
    sampler uDestTextureSmplr [[id(12)]];
};

struct main0_out
{
    float4 oFragColor [[color(0)]];
};

struct main0_in
{
    float3 vMaskTexCoord0 [[user(locn0)]];
    float3 vMaskTexCoord1 [[user(locn1)]];
    float2 vColorTexCoord0 [[user(locn2)]];
    float2 vColorTexCoord1 [[user(locn3)]];
};

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

float sampleMask(thread const float& maskAlpha, thread const texture2d<float> maskTexture, thread const sampler maskTextureSmplr, thread const float3& maskTexCoord, thread const int& maskCtrl)
{
    if (maskCtrl == 0)
    {
        return maskAlpha;
    }
    float coverage = maskTexture.sample(maskTextureSmplr, maskTexCoord.xy).x + maskTexCoord.z;
    if ((maskCtrl & 1) != 0)
    {
        coverage = abs(coverage);
    }
    else
    {
        coverage = 1.0 - abs(1.0 - mod(coverage, 2.0));
    }
    return fast::min(maskAlpha, coverage);
}

float2 computeColorTexCoord(thread const float2& colorTexCoord, thread const int& colorFilter, thread const float4& filterParams0, thread const float4& filterParams1)
{
    return colorTexCoord;
}

float4 sampleColor(thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, colorTexCoord);
}

float4 filterColor(thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread float2& colorTexCoord, thread const int& colorFilter, thread const float4& filterParams0, thread const float4& filterParams1)
{
    float2 param = colorTexCoord;
    int param_1 = colorFilter;
    float4 param_2 = filterParams0;
    float4 param_3 = filterParams1;
    colorTexCoord = computeColorTexCoord(param, param_1, param_2, param_3);
    float2 param_4 = colorTexCoord;
    return sampleColor(colorTexture, colorTextureSmplr, param_4);
}

float4 composite(thread const float4& color, thread const texture2d<float> destTexture, thread const sampler destTextureSmplr, thread const float2& fragCoord)
{
    return color;
}

fragment main0_out main0(main0_in in [[stage_in]], constant spvDescriptorSetBuffer0& spvDescriptorSet0 [[buffer(0)]], float4 gl_FragCoord [[position]])
{
    main0_out out = {};
    int maskCtrl0 = ((*spvDescriptorSet0.uCtrl) & 3) >> 0;
    int maskCtrl1 = ((*spvDescriptorSet0.uCtrl) & 4) >> 2;
    float maskAlpha = 1.0;
    float param = maskAlpha;
    float3 param_1 = in.vMaskTexCoord0;
    int param_2 = maskCtrl0;
    maskAlpha = sampleMask(param, spvDescriptorSet0.uMaskTexture0, spvDescriptorSet0.uMaskTexture0Smplr, param_1, param_2);
    float param_3 = maskAlpha;
    float3 param_4 = in.vMaskTexCoord1;
    int param_5 = maskCtrl1;
    maskAlpha = sampleMask(param_3, spvDescriptorSet0.uMaskTexture1, spvDescriptorSet0.uMaskTexture1Smplr, param_4, param_5);
    int color0Filter = ((*spvDescriptorSet0.uCtrl) & 56) >> 0;
    float2 param_6 = in.vColorTexCoord0;
    int param_7 = color0Filter;
    float4 param_8 = (*spvDescriptorSet0.uFilterParams0);
    float4 param_9 = (*spvDescriptorSet0.uFilterParams1);
    float4 _171 = filterColor(spvDescriptorSet0.uColorTexture0, spvDescriptorSet0.uColorTexture0Smplr, param_6, param_7, param_8, param_9);
    float4 color = _171;
    if (((*spvDescriptorSet0.uCtrl) & 64) != 0)
    {
        float2 param_10 = in.vColorTexCoord1;
        color *= sampleColor(spvDescriptorSet0.uColorTexture1, spvDescriptorSet0.uColorTexture1Smplr, param_10);
    }
    color *= float4(maskAlpha);
    float4 param_11 = color;
    float2 param_12 = gl_FragCoord.xy;
    out.oFragColor = composite(param_11, spvDescriptorSet0.uDestTexture, spvDescriptorSet0.uDestTextureSmplr, param_12);
    return out;
}

