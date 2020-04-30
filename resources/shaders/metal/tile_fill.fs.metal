// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bFillTileMap
{
    int iFillTileMap[1];
};

struct bFills
{
    uint2 iFills[1];
};

struct bNextFills
{
    int iNextFills[1];
};

struct main0_out
{
    float4 oFragColor [[color(0)]];
};

struct main0_in
{
    float2 vTileSubCoord [[user(locn0)]];
    uint vMaskTileIndex0 [[user(locn1)]];
    int vMaskTileBackdrop0 [[user(locn2)]];
    float2 vColorTexCoord0 [[user(locn3)]];
    float4 vBaseColor [[user(locn4)]];
    float vTileCtrl [[user(locn5)]];
};

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
    return areaLUT.sample(areaLUTSmplr, (float2(y + 8.0, abs(d * dX)) / float2(16.0))) * dX;
}

static inline __attribute__((always_inline))
float4 calculateFillAlpha(thread const int2& tileSubCoord, thread const uint& tileIndex, const device bFillTileMap& v_236, const device bFills& v_260, thread texture2d<float> uAreaLUT, thread const sampler uAreaLUTSmplr, const device bNextFills& v_343)
{
    int fillIndex = v_236.iFillTileMap[tileIndex];
    if (fillIndex < 0)
    {
        return float4(0.0);
    }
    float4 coverages = float4(0.0);
    do
    {
        uint2 fill = v_260.iFills[fillIndex];
        float2 from = float2(float(fill.y & 15u), float((fill.y >> 4u) & 15u)) + (float2(float(fill.x & 255u), float((fill.x >> 8u) & 255u)) / float2(256.0));
        float2 to = float2(float((fill.y >> 8u) & 15u), float((fill.y >> 12u) & 15u)) + (float2(float((fill.x >> 16u) & 255u), float((fill.x >> 24u) & 255u)) / float2(256.0));
        float2 param = from - (float2(tileSubCoord) + float2(0.5));
        float2 param_1 = to - (float2(tileSubCoord) + float2(0.5));
        coverages += computeCoverage(param, param_1, uAreaLUT, uAreaLUTSmplr);
        fillIndex = v_343.iNextFills[fillIndex];
    } while (fillIndex >= 0);
    return coverages;
}

static inline __attribute__((always_inline))
float4 filterRadialGradient(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTextureSize, thread const float2& fragCoord, thread const float2& framebufferSize, thread const float4& filterParams0, thread const float4& filterParams1)
{
    float2 lineFrom = filterParams0.xy;
    float2 lineVector = filterParams0.zw;
    float2 radii = filterParams1.xy;
    float2 uvOrigin = filterParams1.zw;
    float2 dP = colorTexCoord - lineFrom;
    float2 dC = lineVector;
    float dR = radii.y - radii.x;
    float a = dot(dC, dC) - (dR * dR);
    float b = dot(dP, dC) + (radii.x * dR);
    float c = dot(dP, dP) - (radii.x * radii.x);
    float discrim = (b * b) - (a * c);
    float4 color = float4(0.0);
    if (abs(discrim) >= 9.9999997473787516355514526367188e-06)
    {
        float2 ts = float2((float2(1.0, -1.0) * sqrt(discrim)) + float2(b)) / float2(a);
        if (ts.x > ts.y)
        {
            ts = ts.yx;
        }
        float _722;
        if (ts.x >= 0.0)
        {
            _722 = ts.x;
        }
        else
        {
            _722 = ts.y;
        }
        float t = _722;
        color = colorTexture.sample(colorTextureSmplr, (uvOrigin + float2(fast::clamp(t, 0.0, 1.0), 0.0)));
    }
    return color;
}

static inline __attribute__((always_inline))
float4 filterBlur(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTextureSize, thread const float4& filterParams0, thread const float4& filterParams1)
{
    float2 srcOffsetScale = filterParams0.xy / colorTextureSize;
    int support = int(filterParams0.z);
    float3 gaussCoeff = filterParams1.xyz;
    float gaussSum = gaussCoeff.x;
    float4 color = colorTexture.sample(colorTextureSmplr, colorTexCoord) * gaussCoeff.x;
    float2 _767 = gaussCoeff.xy * gaussCoeff.yz;
    gaussCoeff = float3(_767.x, _767.y, gaussCoeff.z);
    for (int i = 1; i <= support; i += 2)
    {
        float gaussPartialSum = gaussCoeff.x;
        float2 _787 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_787.x, _787.y, gaussCoeff.z);
        gaussPartialSum += gaussCoeff.x;
        float2 srcOffset = srcOffsetScale * (float(i) + (gaussCoeff.x / gaussPartialSum));
        color += ((colorTexture.sample(colorTextureSmplr, (colorTexCoord - srcOffset)) + colorTexture.sample(colorTextureSmplr, (colorTexCoord + srcOffset))) * gaussPartialSum);
        gaussSum += (2.0 * gaussPartialSum);
        float2 _827 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_827.x, _827.y, gaussCoeff.z);
    }
    return color / float4(gaussSum);
}

static inline __attribute__((always_inline))
float filterTextSample1Tap(thread const float& offset, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, (colorTexCoord + float2(offset, 0.0))).x;
}

static inline __attribute__((always_inline))
void filterTextSample9Tap(thread float4& outAlphaLeft, thread float& outAlphaCenter, thread float4& outAlphaRight, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord, thread const float4& kernel0, thread const float& onePixel)
{
    bool wide = kernel0.x > 0.0;
    float _405;
    if (wide)
    {
        float param = (-4.0) * onePixel;
        float2 param_1 = colorTexCoord;
        _405 = filterTextSample1Tap(param, colorTexture, colorTextureSmplr, param_1);
    }
    else
    {
        _405 = 0.0;
    }
    float param_2 = (-3.0) * onePixel;
    float2 param_3 = colorTexCoord;
    float param_4 = (-2.0) * onePixel;
    float2 param_5 = colorTexCoord;
    float param_6 = (-1.0) * onePixel;
    float2 param_7 = colorTexCoord;
    outAlphaLeft = float4(_405, filterTextSample1Tap(param_2, colorTexture, colorTextureSmplr, param_3), filterTextSample1Tap(param_4, colorTexture, colorTextureSmplr, param_5), filterTextSample1Tap(param_6, colorTexture, colorTextureSmplr, param_7));
    float param_8 = 0.0;
    float2 param_9 = colorTexCoord;
    outAlphaCenter = filterTextSample1Tap(param_8, colorTexture, colorTextureSmplr, param_9);
    float param_10 = 1.0 * onePixel;
    float2 param_11 = colorTexCoord;
    float param_12 = 2.0 * onePixel;
    float2 param_13 = colorTexCoord;
    float param_14 = 3.0 * onePixel;
    float2 param_15 = colorTexCoord;
    float _465;
    if (wide)
    {
        float param_16 = 4.0 * onePixel;
        float2 param_17 = colorTexCoord;
        _465 = filterTextSample1Tap(param_16, colorTexture, colorTextureSmplr, param_17);
    }
    else
    {
        _465 = 0.0;
    }
    outAlphaRight = float4(filterTextSample1Tap(param_10, colorTexture, colorTextureSmplr, param_11), filterTextSample1Tap(param_12, colorTexture, colorTextureSmplr, param_13), filterTextSample1Tap(param_14, colorTexture, colorTextureSmplr, param_15), _465);
}

static inline __attribute__((always_inline))
float filterTextConvolve7Tap(thread const float4& alpha0, thread const float3& alpha1, thread const float4& kernel0)
{
    return dot(alpha0, kernel0) + dot(alpha1, kernel0.zyx);
}

static inline __attribute__((always_inline))
float filterTextGammaCorrectChannel(thread const float& bgColor, thread const float& fgColor, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr)
{
    return gammaLUT.sample(gammaLUTSmplr, float2(fgColor, 1.0 - bgColor)).x;
}

static inline __attribute__((always_inline))
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

static inline __attribute__((always_inline))
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

static inline __attribute__((always_inline))
float4 sampleColor(thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, colorTexCoord);
}

static inline __attribute__((always_inline))
float4 filterNone(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr)
{
    float2 param = colorTexCoord;
    return sampleColor(colorTexture, colorTextureSmplr, param);
}

static inline __attribute__((always_inline))
float4 filterColor(thread const float2& colorTexCoord, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr, thread const float2& colorTextureSize, thread const float2& fragCoord, thread const float2& framebufferSize, thread const float4& filterParams0, thread const float4& filterParams1, thread const float4& filterParams2, thread const int& colorFilter)
{
    switch (colorFilter)
    {
        case 1:
        {
            float2 param = colorTexCoord;
            float2 param_1 = colorTextureSize;
            float2 param_2 = fragCoord;
            float2 param_3 = framebufferSize;
            float4 param_4 = filterParams0;
            float4 param_5 = filterParams1;
            return filterRadialGradient(param, colorTexture, colorTextureSmplr, param_1, param_2, param_3, param_4, param_5);
        }
        case 3:
        {
            float2 param_6 = colorTexCoord;
            float2 param_7 = colorTextureSize;
            float4 param_8 = filterParams0;
            float4 param_9 = filterParams1;
            return filterBlur(param_6, colorTexture, colorTextureSmplr, param_7, param_8, param_9);
        }
        case 2:
        {
            float2 param_10 = colorTexCoord;
            float2 param_11 = colorTextureSize;
            float4 param_12 = filterParams0;
            float4 param_13 = filterParams1;
            float4 param_14 = filterParams2;
            return filterText(param_10, colorTexture, colorTextureSmplr, gammaLUT, gammaLUTSmplr, param_11, param_12, param_13, param_14);
        }
    }
    float2 param_15 = colorTexCoord;
    return filterNone(param_15, colorTexture, colorTextureSmplr);
}

static inline __attribute__((always_inline))
float4 combineColor0(thread const float4& destColor, thread const float4& srcColor, thread const int& op)
{
    switch (op)
    {
        case 1:
        {
            return float4(srcColor.xyz, srcColor.w * destColor.w);
        }
        case 2:
        {
            return float4(destColor.xyz, srcColor.w * destColor.w);
        }
    }
    return destColor;
}

static inline __attribute__((always_inline))
float4 calculateColorWithMaskAlpha(thread const float& maskAlpha, thread const float4& baseColor, thread const float2& colorTexCoord0, thread const float2& fragCoord, thread const int& ctrl, thread texture2d<float> uColorTexture0, thread const sampler uColorTexture0Smplr, thread texture2d<float> uGammaLUT, thread const sampler uGammaLUTSmplr, thread float2 uColorTextureSize0, thread float2 uFramebufferSize, thread float4 uFilterParams0, thread float4 uFilterParams1, thread float4 uFilterParams2)
{
    float4 color = baseColor;
    int color0Combine = (ctrl >> 6) & 3;
    if (color0Combine != 0)
    {
        int color0Filter = (ctrl >> 4) & 3;
        float2 param = colorTexCoord0;
        float2 param_1 = uColorTextureSize0;
        float2 param_2 = fragCoord;
        float2 param_3 = uFramebufferSize;
        float4 param_4 = uFilterParams0;
        float4 param_5 = uFilterParams1;
        float4 param_6 = uFilterParams2;
        int param_7 = color0Filter;
        float4 color0 = filterColor(param, uColorTexture0, uColorTexture0Smplr, uGammaLUT, uGammaLUTSmplr, param_1, param_2, param_3, param_4, param_5, param_6, param_7);
        float4 param_8 = color;
        float4 param_9 = color0;
        int param_10 = color0Combine;
        color = combineColor0(param_8, param_9, param_10);
    }
    color.w *= maskAlpha;
    float3 _951 = color.xyz * color.w;
    color = float4(_951.x, _951.y, _951.z, color.w);
    return color;
}

static inline __attribute__((always_inline))
float4 calculateColor(thread const int& tileCtrl, thread const int& ctrl, const device bFillTileMap& v_236, const device bFills& v_260, thread texture2d<float> uAreaLUT, thread const sampler uAreaLUTSmplr, const device bNextFills& v_343, thread texture2d<float> uColorTexture0, thread const sampler uColorTexture0Smplr, thread texture2d<float> uGammaLUT, thread const sampler uGammaLUTSmplr, thread float2 uColorTextureSize0, thread float2 uFramebufferSize, thread float4 uFilterParams0, thread float4 uFilterParams1, thread float4 uFilterParams2, thread uint& vMaskTileIndex0, thread float2& vTileSubCoord, thread int& vMaskTileBackdrop0, thread float4& vBaseColor, thread float2& vColorTexCoord0, thread float4& gl_FragCoord)
{
    float maskAlpha = 1.0;
    int maskCtrl0 = (ctrl >> 0) & 1;
    int maskTileCtrl0 = (tileCtrl >> 0) & 3;
    uint maskTileIndex0 = vMaskTileIndex0;
    if ((maskCtrl0 != 0) && (maskTileCtrl0 != 0))
    {
        int2 tileSubCoord = int2(floor(vTileSubCoord));
        int2 param = tileSubCoord;
        uint param_1 = maskTileIndex0;
        float4 alphas = calculateFillAlpha(param, param_1, v_236, v_260, uAreaLUT, uAreaLUTSmplr, v_343) + float4(float(vMaskTileBackdrop0));
        maskAlpha = alphas.x;
    }
    float param_2 = maskAlpha;
    float4 param_3 = vBaseColor;
    float2 param_4 = vColorTexCoord0;
    float2 param_5 = gl_FragCoord.xy;
    int param_6 = ctrl;
    return calculateColorWithMaskAlpha(param_2, param_3, param_4, param_5, param_6, uColorTexture0, uColorTexture0Smplr, uGammaLUT, uGammaLUTSmplr, uColorTextureSize0, uFramebufferSize, uFilterParams0, uFilterParams1, uFilterParams2);
}

fragment main0_out main0(main0_in in [[stage_in]], constant int& uCtrl [[buffer(8)]], constant float2& uColorTextureSize0 [[buffer(3)]], constant float2& uFramebufferSize [[buffer(4)]], constant float4& uFilterParams0 [[buffer(5)]], constant float4& uFilterParams1 [[buffer(6)]], constant float4& uFilterParams2 [[buffer(7)]], const device bFillTileMap& v_236 [[buffer(0)]], const device bFills& v_260 [[buffer(1)]], const device bNextFills& v_343 [[buffer(2)]], texture2d<float> uAreaLUT [[texture(0)]], texture2d<float> uColorTexture0 [[texture(1)]], texture2d<float> uGammaLUT [[texture(2)]], sampler uAreaLUTSmplr [[sampler(0)]], sampler uColorTexture0Smplr [[sampler(1)]], sampler uGammaLUTSmplr [[sampler(2)]], float4 gl_FragCoord [[position]])
{
    main0_out out = {};
    int param = int(in.vTileCtrl);
    int param_1 = uCtrl;
    out.oFragColor = calculateColor(param, param_1, v_236, v_260, uAreaLUT, uAreaLUTSmplr, v_343, uColorTexture0, uColorTexture0Smplr, uGammaLUT, uGammaLUTSmplr, uColorTextureSize0, uFramebufferSize, uFilterParams0, uFilterParams1, uFilterParams2, in.vMaskTileIndex0, in.vTileSubCoord, in.vMaskTileBackdrop0, in.vBaseColor, in.vColorTexCoord0, gl_FragCoord);
    return out;
}

