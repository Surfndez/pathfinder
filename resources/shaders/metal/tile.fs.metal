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
    texture2d<float> uGammaLUT [[id(7)]];
    sampler uGammaLUTSmplr [[id(8)]];
    constant float2* uColorTexture0Size [[id(9)]];
    constant float4* uFilterParams0 [[id(10)]];
    constant float4* uFilterParams1 [[id(11)]];
    constant float4* uFilterParams2 [[id(12)]];
    texture2d<float> uColorTexture1 [[id(13)]];
    sampler uColorTexture1Smplr [[id(14)]];
    texture2d<float> uDestTexture [[id(15)]];
    sampler uDestTextureSmplr [[id(16)]];
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

float4 filterBlur(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTextureSize, thread const float4& filterParams0, thread const float4& filterParams1)
{
    float2 srcOffsetScale = filterParams0.xy / colorTextureSize;
    int support = int(filterParams0.z);
    float3 gaussCoeff = filterParams1.xyz;
    float gaussSum = gaussCoeff.x;
    float4 color = colorTexture.sample(colorTextureSmplr, colorTexCoord) * gaussCoeff.x;
    float2 _381 = gaussCoeff.xy * gaussCoeff.yz;
    gaussCoeff = float3(_381.x, _381.y, gaussCoeff.z);
    for (int i = 1; i <= support; i += 2)
    {
        float gaussPartialSum = gaussCoeff.x;
        float2 _401 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_401.x, _401.y, gaussCoeff.z);
        gaussPartialSum += gaussCoeff.x;
        float2 srcOffset = srcOffsetScale * (float(i) + (gaussCoeff.x / gaussPartialSum));
        color += ((colorTexture.sample(colorTextureSmplr, (colorTexCoord - srcOffset)) + colorTexture.sample(colorTextureSmplr, (colorTexCoord + srcOffset))) * gaussPartialSum);
        gaussSum += (2.0 * gaussPartialSum);
        float2 _441 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_441.x, _441.y, gaussCoeff.z);
    }
    color /= float4(gaussSum);
    float3 _455 = color.xyz * color.w;
    color = float4(_455.x, _455.y, _455.z, color.w);
    return color;
}

float filterTextSample1Tap(thread const float& offset, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, (colorTexCoord + float2(offset, 0.0))).x;
}

void filterTextSample9Tap(thread float4& outAlphaLeft, thread float& outAlphaCenter, thread float4& outAlphaRight, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord, thread const float4& kernel0, thread const float& onePixel)
{
    bool wide = kernel0.x > 0.0;
    float _129;
    if (wide)
    {
        float param = (-4.0) * onePixel;
        float2 param_1 = colorTexCoord;
        _129 = filterTextSample1Tap(param, colorTexture, colorTextureSmplr, param_1);
    }
    else
    {
        _129 = 0.0;
    }
    float param_2 = (-3.0) * onePixel;
    float2 param_3 = colorTexCoord;
    float param_4 = (-2.0) * onePixel;
    float2 param_5 = colorTexCoord;
    float param_6 = (-1.0) * onePixel;
    float2 param_7 = colorTexCoord;
    outAlphaLeft = float4(_129, filterTextSample1Tap(param_2, colorTexture, colorTextureSmplr, param_3), filterTextSample1Tap(param_4, colorTexture, colorTextureSmplr, param_5), filterTextSample1Tap(param_6, colorTexture, colorTextureSmplr, param_7));
    float param_8 = 0.0;
    float2 param_9 = colorTexCoord;
    outAlphaCenter = filterTextSample1Tap(param_8, colorTexture, colorTextureSmplr, param_9);
    float param_10 = 1.0 * onePixel;
    float2 param_11 = colorTexCoord;
    float param_12 = 2.0 * onePixel;
    float2 param_13 = colorTexCoord;
    float param_14 = 3.0 * onePixel;
    float2 param_15 = colorTexCoord;
    float _189;
    if (wide)
    {
        float param_16 = 4.0 * onePixel;
        float2 param_17 = colorTexCoord;
        _189 = filterTextSample1Tap(param_16, colorTexture, colorTextureSmplr, param_17);
    }
    else
    {
        _189 = 0.0;
    }
    outAlphaRight = float4(filterTextSample1Tap(param_10, colorTexture, colorTextureSmplr, param_11), filterTextSample1Tap(param_12, colorTexture, colorTextureSmplr, param_13), filterTextSample1Tap(param_14, colorTexture, colorTextureSmplr, param_15), _189);
}

float filterTextConvolve7Tap(thread const float4& alpha0, thread const float3& alpha1, thread const float4& kernel0)
{
    return dot(alpha0, kernel0) + dot(alpha1, kernel0.zyx);
}

float filterTextGammaCorrectChannel(thread const float& bgColor, thread const float& fgColor, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr)
{
    return gammaLUT.sample(gammaLUTSmplr, float2(fgColor, 1.0 - bgColor)).x;
}

float3 filterTextGammaCorrect(thread const float3& bgColor, thread const float3& fgColor, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr)
{
    float param = bgColor.x;
    float param_1 = fgColor.x;
    float param_2 = bgColor.y;
    float param_3 = fgColor.y;
    float param_4 = bgColor.z;
    float param_5 = fgColor.z;
    return float3(filterTextGammaCorrectChannel(param, param_1, gammaLUT, gammaLUTSmplr), filterTextGammaCorrectChannel(param_2, param_3, gammaLUT, gammaLUTSmplr), filterTextGammaCorrectChannel(param_4, param_5, gammaLUT, gammaLUTSmplr));
}

float4 filterText(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr, thread const float2& colorTextureSize, thread const float4& filterParams0, thread const float4& filterParams1, thread const float4& filterParams2)
{
    float4 kernel0 = filterParams0;
    float3 bgColor = filterParams1.xyz;
    float3 fgColor = filterParams2.xyz;
    bool gammaCorrectionEnabled = filterParams2.w != 0.0;
    float3 alpha;
    if (kernel0.w == 0.0)
    {
        alpha = colorTexture.sample(colorTextureSmplr, colorTexCoord).xxx;
    }
    else
    {
        float2 param_3 = colorTexCoord;
        float4 param_4 = kernel0;
        float param_5 = 1.0 / colorTextureSize.x;
        float4 param;
        float param_1;
        float4 param_2;
        filterTextSample9Tap(param, param_1, param_2, colorTexture, colorTextureSmplr, param_3, param_4, param_5);
        float4 alphaLeft = param;
        float alphaCenter = param_1;
        float4 alphaRight = param_2;
        float4 param_6 = alphaLeft;
        float3 param_7 = float3(alphaCenter, alphaRight.xy);
        float4 param_8 = kernel0;
        float r = filterTextConvolve7Tap(param_6, param_7, param_8);
        float4 param_9 = float4(alphaLeft.yzw, alphaCenter);
        float3 param_10 = alphaRight.xyz;
        float4 param_11 = kernel0;
        float g = filterTextConvolve7Tap(param_9, param_10, param_11);
        float4 param_12 = float4(alphaLeft.zw, alphaCenter, alphaRight.x);
        float3 param_13 = alphaRight.yzw;
        float4 param_14 = kernel0;
        float b = filterTextConvolve7Tap(param_12, param_13, param_14);
        alpha = float3(r, g, b);
    }
    if (gammaCorrectionEnabled)
    {
        float3 param_15 = bgColor;
        float3 param_16 = alpha;
        alpha = filterTextGammaCorrect(param_15, param_16, gammaLUT, gammaLUTSmplr);
    }
    return float4(mix(bgColor, fgColor, alpha), 1.0);
}

float4 sampleColor(thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, colorTexCoord);
}

float4 filterNone(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr)
{
    float2 param = colorTexCoord;
    return sampleColor(colorTexture, colorTextureSmplr, param);
}

float4 filterColor(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr, thread const float2& colorTextureSize, thread const float4& filterParams0, thread const float4& filterParams1, thread const float4& filterParams2, thread const int& colorFilter)
{
    switch (colorFilter)
    {
        case 3:
        {
            float2 param = colorTexCoord;
            float2 param_1 = colorTextureSize;
            float4 param_2 = filterParams0;
            float4 param_3 = filterParams1;
            return filterBlur(param, colorTexture, colorTextureSmplr, param_1, param_2, param_3);
        }
        case 2:
        {
            float2 param_4 = colorTexCoord;
            float2 param_5 = colorTextureSize;
            float4 param_6 = filterParams0;
            float4 param_7 = filterParams1;
            float4 param_8 = filterParams2;
            return filterText(param_4, colorTexture, colorTextureSmplr, gammaLUT, gammaLUTSmplr, param_5, param_6, param_7, param_8);
        }
    }
    float2 param_9 = colorTexCoord;
    return filterNone(param_9, colorTexture, colorTextureSmplr);
}

float4 composite(thread const float4& color, thread const texture2d<float> destTexture, thread const sampler destTextureSmplr, thread const float2& fragCoord)
{
    return color;
}

fragment main0_out main0(main0_in in [[stage_in]], constant spvDescriptorSetBuffer0& spvDescriptorSet0 [[buffer(0)]], float4 gl_FragCoord [[position]])
{
    main0_out out = {};
    int maskCtrl0 = ((*spvDescriptorSet0.uCtrl) >> 0) & 3;
    int maskCtrl1 = ((*spvDescriptorSet0.uCtrl) >> 2) & 3;
    float maskAlpha = 1.0;
    float param = maskAlpha;
    float3 param_1 = in.vMaskTexCoord0;
    int param_2 = maskCtrl0;
    maskAlpha = sampleMask(param, spvDescriptorSet0.uMaskTexture0, spvDescriptorSet0.uMaskTexture0Smplr, param_1, param_2);
    float param_3 = maskAlpha;
    float3 param_4 = in.vMaskTexCoord1;
    int param_5 = maskCtrl1;
    maskAlpha = sampleMask(param_3, spvDescriptorSet0.uMaskTexture1, spvDescriptorSet0.uMaskTexture1Smplr, param_4, param_5);
    int color0Filter = ((*spvDescriptorSet0.uCtrl) >> 4) & 3;
    float2 param_6 = in.vColorTexCoord0;
    float2 param_7 = (*spvDescriptorSet0.uColorTexture0Size);
    float4 param_8 = (*spvDescriptorSet0.uFilterParams0);
    float4 param_9 = (*spvDescriptorSet0.uFilterParams1);
    float4 param_10 = (*spvDescriptorSet0.uFilterParams2);
    int param_11 = color0Filter;
    float4 color = filterColor(param_6, spvDescriptorSet0.uColorTexture0, spvDescriptorSet0.uColorTexture0Smplr, spvDescriptorSet0.uGammaLUT, spvDescriptorSet0.uGammaLUTSmplr, param_7, param_8, param_9, param_10, param_11);
    if ((((*spvDescriptorSet0.uCtrl) >> 6) & 1) != 0)
    {
        float2 param_12 = in.vColorTexCoord1;
        color *= sampleColor(spvDescriptorSet0.uColorTexture1, spvDescriptorSet0.uColorTexture1Smplr, param_12);
    }
    color *= float4(maskAlpha);
    float4 param_13 = color;
    float2 param_14 = gl_FragCoord.xy;
    out.oFragColor = composite(param_13, spvDescriptorSet0.uDestTexture, spvDescriptorSet0.uDestTextureSmplr, param_14);
    return out;
}

