// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct main0_out
{
    float4 oFragColor [[color(0)]];
};

struct main0_in
{
    float3 vMaskTexCoord0 [[user(locn0)]];
    float4 vBaseColor [[user(locn2)]];
    float vTileCtrl [[user(locn3)]];
};

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

static inline __attribute__((always_inline))
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

static inline __attribute__((always_inline))
void calculateColor(thread const int& tileCtrl, thread const int& ctrl, thread texture2d<float> uMaskTexture0, thread const sampler uMaskTexture0Smplr, thread float3& vMaskTexCoord0, thread float4& vBaseColor, thread float4& oFragColor)
{
    int maskCtrl0 = (tileCtrl >> 0) & 3;
    float maskAlpha = 1.0;
    float param = maskAlpha;
    float3 param_1 = vMaskTexCoord0;
    int param_2 = maskCtrl0;
    maskAlpha = sampleMask(param, uMaskTexture0, uMaskTexture0Smplr, param_1, param_2);
    float4 color = vBaseColor;
    color.w *= maskAlpha;
    float3 _101 = color.xyz * color.w;
    color = float4(_101.x, _101.y, _101.z, color.w);
    oFragColor = color;
}

fragment main0_out main0(main0_in in [[stage_in]], constant int& uCtrl [[buffer(0)]], texture2d<float> uMaskTexture0 [[texture(0)]], sampler uMaskTexture0Smplr [[sampler(0)]])
{
    main0_out out = {};
    int param = int(in.vTileCtrl);
    int param_1 = uCtrl;
    calculateColor(param, param_1, uMaskTexture0, uMaskTexture0Smplr, in.vMaskTexCoord0, in.vBaseColor, out.oFragColor);
    return out;
}

