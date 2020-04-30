// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

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

struct bFirstTiles
{
    int iFirstTiles[1];
};

struct bTiles
{
    uint iTiles[1];
};

struct bNextTiles
{
    int iNextTiles[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 4u, 1u);

constant spvUnsafeArray<float4, 4> _1023 = spvUnsafeArray<float4, 4>({ float4(0.0), float4(0.0), float4(0.0), float4(0.0) });

static inline __attribute__((always_inline))
void lookupTextureMetadata(thread const int& color, thread float2x2& outColorTexMatrix0, thread float4& outColorTexOffsets, thread float4& outBaseColor, thread int2 uTextureMetadataSize, thread texture2d<float> uTextureMetadata, thread const sampler uTextureMetadataSmplr)
{
    float2 textureMetadataScale = float2(1.0) / float2(uTextureMetadataSize);
    float2 metadataEntryCoord = float2(float((color % 128) * 4), float(color / 128));
    float2 colorTexMatrix0Coord = (metadataEntryCoord + float2(0.5)) * textureMetadataScale;
    float2 colorTexOffsetsCoord = (metadataEntryCoord + float2(1.5, 0.5)) * textureMetadataScale;
    float2 baseColorCoord = (metadataEntryCoord + float2(2.5, 0.5)) * textureMetadataScale;
    float4 _1000 = uTextureMetadata.sample(uTextureMetadataSmplr, colorTexMatrix0Coord, level(0.0));
    outColorTexMatrix0 = float2x2(float2(_1000.xy), float2(_1000.zw));
    outColorTexOffsets = uTextureMetadata.sample(uTextureMetadataSmplr, colorTexOffsetsCoord, level(0.0));
    outBaseColor = uTextureMetadata.sample(uTextureMetadataSmplr, baseColorCoord, level(0.0));
}

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

static inline __attribute__((always_inline))
float4 calculateFillAlpha(thread const int2& tileSubCoord, thread const uint& tileIndex, const device bFillTileMap& v_241, const device bFills& v_264, thread texture2d<float> uAreaLUT, thread const sampler uAreaLUTSmplr, const device bNextFills& v_347)
{
    int fillIndex = v_241.iFillTileMap[tileIndex];
    if (fillIndex < 0)
    {
        return float4(0.0);
    }
    float4 coverages = float4(0.0);
    do
    {
        uint2 fill = v_264.iFills[fillIndex];
        float2 from = float2(float(fill.y & 15u), float((fill.y >> 4u) & 15u)) + (float2(float(fill.x & 255u), float((fill.x >> 8u) & 255u)) / float2(256.0));
        float2 to = float2(float((fill.y >> 8u) & 15u), float((fill.y >> 12u) & 15u)) + (float2(float((fill.x >> 16u) & 255u), float((fill.x >> 24u) & 255u)) / float2(256.0));
        float2 param = from - (float2(tileSubCoord) + float2(0.5));
        float2 param_1 = to - (float2(tileSubCoord) + float2(0.5));
        coverages += computeCoverage(param, param_1, uAreaLUT, uAreaLUTSmplr);
        fillIndex = v_347.iNextFills[fillIndex];
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
        float _726;
        if (ts.x >= 0.0)
        {
            _726 = ts.x;
        }
        else
        {
            _726 = ts.y;
        }
        float t = _726;
        color = colorTexture.sample(colorTextureSmplr, (uvOrigin + float2(fast::clamp(t, 0.0, 1.0), 0.0)), level(0.0));
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
    float4 color = colorTexture.sample(colorTextureSmplr, colorTexCoord, level(0.0)) * gaussCoeff.x;
    float2 _771 = gaussCoeff.xy * gaussCoeff.yz;
    gaussCoeff = float3(_771.x, _771.y, gaussCoeff.z);
    for (int i = 1; i <= support; i += 2)
    {
        float gaussPartialSum = gaussCoeff.x;
        float2 _791 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_791.x, _791.y, gaussCoeff.z);
        gaussPartialSum += gaussCoeff.x;
        float2 srcOffset = srcOffsetScale * (float(i) + (gaussCoeff.x / gaussPartialSum));
        color += ((colorTexture.sample(colorTextureSmplr, (colorTexCoord - srcOffset), level(0.0)) + colorTexture.sample(colorTextureSmplr, (colorTexCoord + srcOffset), level(0.0))) * gaussPartialSum);
        gaussSum += (2.0 * gaussPartialSum);
        float2 _831 = gaussCoeff.xy * gaussCoeff.yz;
        gaussCoeff = float3(_831.x, _831.y, gaussCoeff.z);
    }
    return color / float4(gaussSum);
}

static inline __attribute__((always_inline))
float filterTextSample1Tap(thread const float& offset, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord)
{
    return colorTexture.sample(colorTextureSmplr, (colorTexCoord + float2(offset, 0.0)), level(0.0)).x;
}

static inline __attribute__((always_inline))
void filterTextSample9Tap(thread float4& outAlphaLeft, thread float& outAlphaCenter, thread float4& outAlphaRight, thread const texture2d<float> colorTexture, thread const sampler colorTextureSmplr, thread const float2& colorTexCoord, thread const float4& kernel0, thread const float& onePixel)
{
    bool wide = kernel0.x > 0.0;
    float _409;
    if (wide)
    {
        float param = (-4.0) * onePixel;
        float2 param_1 = colorTexCoord;
        _409 = filterTextSample1Tap(param, colorTexture, colorTextureSmplr, param_1);
    }
    else
    {
        _409 = 0.0;
    }
    float param_2 = (-3.0) * onePixel;
    float2 param_3 = colorTexCoord;
    float param_4 = (-2.0) * onePixel;
    float2 param_5 = colorTexCoord;
    float param_6 = (-1.0) * onePixel;
    float2 param_7 = colorTexCoord;
    outAlphaLeft = float4(_409, filterTextSample1Tap(param_2, colorTexture, colorTextureSmplr, param_3), filterTextSample1Tap(param_4, colorTexture, colorTextureSmplr, param_5), filterTextSample1Tap(param_6, colorTexture, colorTextureSmplr, param_7));
    float param_8 = 0.0;
    float2 param_9 = colorTexCoord;
    outAlphaCenter = filterTextSample1Tap(param_8, colorTexture, colorTextureSmplr, param_9);
    float param_10 = 1.0 * onePixel;
    float2 param_11 = colorTexCoord;
    float param_12 = 2.0 * onePixel;
    float2 param_13 = colorTexCoord;
    float param_14 = 3.0 * onePixel;
    float2 param_15 = colorTexCoord;
    float _469;
    if (wide)
    {
        float param_16 = 4.0 * onePixel;
        float2 param_17 = colorTexCoord;
        _469 = filterTextSample1Tap(param_16, colorTexture, colorTextureSmplr, param_17);
    }
    else
    {
        _469 = 0.0;
    }
    outAlphaRight = float4(filterTextSample1Tap(param_10, colorTexture, colorTextureSmplr, param_11), filterTextSample1Tap(param_12, colorTexture, colorTextureSmplr, param_13), filterTextSample1Tap(param_14, colorTexture, colorTextureSmplr, param_15), _469);
}

static inline __attribute__((always_inline))
float filterTextConvolve7Tap(thread const float4& alpha0, thread const float3& alpha1, thread const float4& kernel0)
{
    return dot(alpha0, kernel0) + dot(alpha1, kernel0.zyx);
}

static inline __attribute__((always_inline))
float filterTextGammaCorrectChannel(thread const float& bgColor, thread const float& fgColor, thread const texture2d<float> gammaLUT, thread const sampler gammaLUTSmplr)
{
    return gammaLUT.sample(gammaLUTSmplr, float2(fgColor, 1.0 - bgColor), level(0.0)).x;
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
        alpha = colorTexture.sample(colorTextureSmplr, colorTexCoord, level(0.0)).xxx;
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
    return colorTexture.sample(colorTextureSmplr, colorTexCoord, level(0.0));
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
    float3 _955 = color.xyz * color.w;
    color = float4(_955.x, _955.y, _955.z, color.w);
    return color;
}

kernel void main0(constant int2& uTextureMetadataSize [[buffer(8)]], constant int& uCtrl [[buffer(9)]], constant float2& uColorTextureSize0 [[buffer(3)]], constant float2& uFramebufferSize [[buffer(4)]], constant float4& uFilterParams0 [[buffer(5)]], constant float4& uFilterParams1 [[buffer(6)]], constant float4& uFilterParams2 [[buffer(7)]], constant float2& uTileSize [[buffer(12)]], const device bFillTileMap& v_241 [[buffer(0)]], const device bFills& v_264 [[buffer(1)]], const device bNextFills& v_347 [[buffer(2)]], const device bFirstTiles& _1039 [[buffer(10)]], const device bTiles& _1060 [[buffer(11)]], const device bNextTiles& _1206 [[buffer(13)]], texture2d<float> uAreaLUT [[texture(0)]], texture2d<float> uColorTexture0 [[texture(1)]], texture2d<float> uGammaLUT [[texture(2)]], texture2d<float> uTextureMetadata [[texture(3)]], texture2d<float, access::read_write> uDestImage [[texture(4)]], sampler uAreaLUTSmplr [[sampler(0)]], sampler uColorTexture0Smplr [[sampler(1)]], sampler uGammaLUTSmplr [[sampler(2)]], sampler uTextureMetadataSmplr [[sampler(3)]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    int maskCtrl0 = (uCtrl >> 0) & 1;
    spvUnsafeArray<float4, 4> colors = spvUnsafeArray<float4, 4>({ float4(0.0), float4(0.0), float4(0.0), float4(0.0) });
    int2 tileSubCoord = int2(gl_LocalInvocationID.xy) * int2(1, 4);
    int2 tileOrigin = int2(0);
    int tileIndex = _1039.iFirstTiles[gl_WorkGroupID.z];
    int overlapCount = 0;
    float2x2 param_1;
    float4 param_2;
    float4 param_3;
    while (tileIndex >= 0)
    {
        overlapCount++;
        uint tileCoord = _1060.iTiles[(tileIndex * 3) + 0];
        uint maskTexCoord = _1060.iTiles[(tileIndex * 3) + 1];
        uint colorCtrl = _1060.iTiles[(tileIndex * 3) + 2];
        tileOrigin = int2(int(tileCoord & 65535u), int(tileCoord >> uint(16)));
        int ctrl = uCtrl;
        int tileColor = int(colorCtrl & 65535u);
        int tileCtrl = int(colorCtrl >> uint(16));
        int param = tileColor;
        lookupTextureMetadata(param, param_1, param_2, param_3, uTextureMetadataSize, uTextureMetadata, uTextureMetadataSmplr);
        float2x2 colorTexMatrix0 = param_1;
        float4 colorTexOffsets = param_2;
        float4 baseColor = param_3;
        int maskTileCtrl0 = (tileCtrl >> 0) & 3;
        float4 maskAlphas = float4(1.0);
        if ((maskCtrl0 != 0) && (maskTileCtrl0 != 0))
        {
            uint maskTileIndex0 = maskTexCoord & 65535u;
            int maskTileBackdrop0 = int(maskTexCoord << uint(8)) >> 24;
            int2 param_4 = tileSubCoord;
            uint param_5 = maskTileIndex0;
            maskAlphas = fast::clamp(abs(calculateFillAlpha(param_4, param_5, v_241, v_264, uAreaLUT, uAreaLUTSmplr, v_347) + float4(float(maskTileBackdrop0))), float4(0.0), float4(1.0));
        }
        for (int yOffset = 0; yOffset < 4; yOffset++)
        {
            int2 fragCoordI = ((tileOrigin * int2(uTileSize)) + tileSubCoord) + int2(0, yOffset);
            float2 fragCoord = float2(fragCoordI) + float2(0.5);
            float2 colorTexCoord0 = (colorTexMatrix0 * fragCoord) + colorTexOffsets.xy;
            float param_6 = maskAlphas[yOffset];
            float4 param_7 = baseColor;
            float2 param_8 = colorTexCoord0;
            float2 param_9 = fragCoord;
            int param_10 = ctrl;
            float4 color = calculateColorWithMaskAlpha(param_6, param_7, param_8, param_9, param_10, uColorTexture0, uColorTexture0Smplr, uGammaLUT, uGammaLUTSmplr, uColorTextureSize0, uFramebufferSize, uFilterParams0, uFilterParams1, uFilterParams2);
            colors[yOffset] = (colors[yOffset] * (1.0 - color.w)) + color;
        }
        tileIndex = _1206.iNextTiles[tileIndex];
    }
    for (int yOffset_1 = 0; yOffset_1 < 4; yOffset_1++)
    {
        int2 fragCoord_1 = ((tileOrigin * int2(uTileSize)) + tileSubCoord) + int2(0, yOffset_1);
        float4 color_1 = colors[yOffset_1];
        if (color_1.w < 1.0)
        {
            color_1 = (uDestImage.read(uint2(fragCoord_1)) * (1.0 - color_1.w)) + color_1;
        }
        uDestImage.write(color_1, uint2(fragCoord_1));
    }
}

