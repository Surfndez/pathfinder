// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bMetadata
{
    int4 iMetadata[1];
};

struct bTiles
{
    uint iTiles[1];
};

struct bIndirectDrawParams
{
    uint iIndirectDrawParams[1];
};

struct bFills
{
    uint iFills[1];
};

constant bool _250 = {};

struct main0_out
{
    float4 oFragColor [[color(0)]];
};

struct main0_in
{
    float2 vFrom [[user(locn0)]];
    float2 vTo [[user(locn1)]];
    uint vPathIndex [[user(locn2)]];
};

static inline __attribute__((always_inline))
uint computeOutcode(thread const float2& p, thread const float4& rect)
{
    uint code = 0u;
    if (p.x < rect.x)
    {
        code |= 1u;
    }
    else
    {
        if (p.x > rect.z)
        {
            code |= 2u;
        }
    }
    if (p.y < rect.y)
    {
        code |= 8u;
    }
    else
    {
        if (p.y > rect.w)
        {
            code |= 4u;
        }
    }
    return code;
}

static inline __attribute__((always_inline))
bool clipLine(thread float4& line, thread const float4& rect, thread float4& outLine)
{
    float2 param = line.xy;
    float4 param_1 = rect;
    float2 param_2 = line.zw;
    float4 param_3 = rect;
    uint2 outcodes = uint2(computeOutcode(param, param_1), computeOutcode(param_2, param_3));
    float2 p;
    while (true)
    {
        if ((outcodes.x | outcodes.y) == 0u)
        {
            outLine = line;
            return true;
        }
        if ((outcodes.x & outcodes.y) != 0u)
        {
            outLine = line;
            return false;
        }
        uint outcode = max(outcodes.x, outcodes.y);
        if ((outcode & 8u) != 0u)
        {
            p = float2(mix(line.x, line.z, (rect.y - line.y) / (line.w - line.y)), rect.y);
        }
        else
        {
            if ((outcode & 4u) != 0u)
            {
                p = float2(mix(line.x, line.z, (rect.w - line.y) / (line.w - line.y)), rect.w);
            }
            else
            {
                if ((outcode & 1u) != 0u)
                {
                    p = float2(rect.x, mix(line.y, line.w, (rect.x - line.x) / (line.z - line.x)));
                }
                else
                {
                    if ((outcode & 2u) != 0u)
                    {
                        p = float2(rect.z, mix(line.y, line.w, (rect.z - line.x) / (line.z - line.x)));
                    }
                }
            }
        }
        if (outcode == outcodes.x)
        {
            line = float4(p.x, p.y, line.z, line.w);
            float2 param_4 = line.xy;
            float4 param_5 = rect;
            outcodes.x = computeOutcode(param_4, param_5);
        }
        else
        {
            line = float4(line.x, line.y, p.x, p.y);
            float2 param_6 = line.zw;
            float4 param_7 = rect;
            outcodes.y = computeOutcode(param_6, param_7);
        }
    }
}

fragment main0_out main0(main0_in in [[stage_in]], constant int2& uFramebufferSize [[buffer(0)]], const device bMetadata& _307 [[buffer(1)]], device bTiles& _350 [[buffer(2)]], device bIndirectDrawParams& _365 [[buffer(3)]], device bFills& _405 [[buffer(4)]], float4 gl_FragCoord [[position]])
{
    main0_out out = {};
    float2 fragCoord = gl_FragCoord.xy;
    fragCoord.y = float(uFramebufferSize.y) - fragCoord.y;
    int2 tileCoord = int2(fragCoord);
    float4 tileRect = fragCoord.xyxy + float4(-0.5, -0.5, 0.5, 0.5);
    float4 param = float4(in.vFrom, in.vTo);
    float4 param_1 = tileRect;
    float4 param_2;
    bool _296 = clipLine(param, param_1, param_2);
    float4 line = param_2;
    bool inBounds = _296;
    if (inBounds)
    {
        int4 pathTileRect = _307.iMetadata[(in.vPathIndex * 2u) + 0u];
        uint pathTileOffset = uint(_307.iMetadata[(in.vPathIndex * 2u) + 1u].x);
        int2 tileOffset = tileCoord - pathTileRect.xy;
        uint tileIndex = pathTileOffset + uint((tileOffset.y * (pathTileRect.z - pathTileRect.x)) + tileOffset.x);
        uint _356 = atomic_fetch_add_explicit((device atomic_uint*)&_350.iTiles[(tileIndex * 4u) + 1u], 0u, memory_order_relaxed);
        uint alphaTileIndex = _356;
        if (alphaTileIndex == 0u)
        {
            uint _368 = atomic_fetch_add_explicit((device atomic_uint*)&_365.iIndirectDrawParams[4], 1u, memory_order_relaxed);
            uint trialAlphaTileIndex = _368;
            uint _374;
            do
            {
                _374 = 0u;
            } while (!atomic_compare_exchange_weak_explicit((device atomic_uint*)&_350.iTiles[(tileIndex * 4u) + 1u], &_374, trialAlphaTileIndex, memory_order_relaxed, memory_order_relaxed) && _374 == 0u);
            alphaTileIndex = _374;
            if (alphaTileIndex == 0u)
            {
                alphaTileIndex = trialAlphaTileIndex;
                _350.iTiles[(tileIndex * 4u) + 1u] = alphaTileIndex;
            }
        }
        float4 localLine = line - tileRect.xyxy;
        uint4 scaledLocalLine = uint4(localLine * float4(256.0));
        uint _401 = atomic_fetch_add_explicit((device atomic_uint*)&_365.iIndirectDrawParams[1], 1u, memory_order_relaxed);
        uint fillIndex = _401;
        _405.iFills[(fillIndex * 3u) + 0u] = scaledLocalLine.x | (scaledLocalLine.y << uint(16));
        _405.iFills[(fillIndex * 3u) + 1u] = scaledLocalLine.z | (scaledLocalLine.w << uint(16));
        _405.iFills[(fillIndex * 3u) + 2u] = alphaTileIndex;
    }
    out.oFragColor = float4(1.0, 0.0, 0.0, 1.0);
    return out;
}

