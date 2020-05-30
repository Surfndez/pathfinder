// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct bInitialTileMap
{
    uint iInitialTileMap[1];
};

struct bTileLinkMap
{
    int2 iTileLinkMap[1];
};

struct bFills
{
    uint iFills[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(16u, 4u, 1u);

struct bTiles
{
    int iTiles[1];
};

static inline __attribute__((always_inline))
bool initFill(thread int& tileIndex, thread int& fillIndex, thread const uint& tileIndexOffset, const device bInitialTileMap& v_133, const device bTileLinkMap& v_151)
{
    tileIndex = int(v_133.iInitialTileMap[tileIndexOffset]);
    while (tileIndex >= 0)
    {
        fillIndex = v_151.iTileLinkMap[tileIndex].x;
        if (fillIndex >= 0)
        {
            return true;
        }
        tileIndex = v_151.iTileLinkMap[tileIndex].y;
    }
    return false;
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
bool nextFill(thread int& tileIndex, thread int& fillIndex, const device bTileLinkMap& v_151, const device bFills& v_171)
{
    fillIndex = int(v_171.iFills[(fillIndex * 3) + 2]);
    if (fillIndex >= 0)
    {
        return true;
    }
    tileIndex = v_151.iTileLinkMap[tileIndex].y;
    while (tileIndex >= 0)
    {
        fillIndex = v_151.iTileLinkMap[tileIndex].x;
        if (fillIndex >= 0)
        {
            return true;
        }
        tileIndex = v_151.iTileLinkMap[tileIndex].y;
    }
    return false;
}

kernel void main0(constant int2& uFramebufferTileSize [[buffer(3)]], const device bInitialTileMap& v_133 [[buffer(0)]], const device bTileLinkMap& v_151 [[buffer(1)]], const device bFills& v_171 [[buffer(2)]], texture2d<float> uAreaLUT [[texture(0)]], texture2d<float, access::write> uDest [[texture(1)]], sampler uAreaLUTSmplr [[sampler(0)]], uint3 gl_LocalInvocationID [[thread_position_in_threadgroup]], uint3 gl_WorkGroupID [[threadgroup_position_in_grid]])
{
    int2 tileSubCoord = int2(gl_LocalInvocationID.xy) * int2(1, 4);
    int2 tileCoord = int2(gl_WorkGroupID.xy);
    uint tileIndexOffset = uint(tileCoord.x + (tileCoord.y * uFramebufferTileSize.x));
    int tileIndex = -1;
    int fillIndex = -1;
    float4 coverages = float4(0.0);
    int param = tileIndex;
    int param_1 = fillIndex;
    uint param_2 = tileIndexOffset;
    bool _251 = initFill(param, param_1, param_2, v_133, v_151);
    tileIndex = param;
    fillIndex = param_1;
    if (_251)
    {
        bool _325;
        int iteration = 0;
        for (;;)
        {
            uint fillFrom = v_171.iFills[(fillIndex * 3) + 0];
            uint fillTo = v_171.iFills[(fillIndex * 3) + 1];
            float4 lineSegment = float4(float(fillFrom & 65535u), float(fillFrom >> uint(16)), float(fillTo & 65535u), float(fillTo >> uint(16))) / float4(256.0);
            float2 param_3 = lineSegment.xy - (float2(tileSubCoord) + float2(0.5));
            float2 param_4 = lineSegment.zw - (float2(tileSubCoord) + float2(0.5));
            coverages += computeCoverage(param_3, param_4, uAreaLUT, uAreaLUTSmplr);
            iteration++;
            bool _315 = iteration < 1024;
            if (_315)
            {
                int param_5 = tileIndex;
                int param_6 = fillIndex;
                bool _322 = nextFill(param_5, param_6, v_151, v_171);
                tileIndex = param_5;
                fillIndex = param_6;
                _325 = _322;
            }
            else
            {
                _325 = _315;
            }
            if (_325)
            {
                continue;
            }
            else
            {
                break;
            }
        }
    }
    int2 destCoord = (tileCoord * int2(16)) + tileSubCoord;
    uDest.write(float4(coverages.xxx, 1.0), uint2((destCoord + int2(0))));
    uDest.write(float4(coverages.yyy, 1.0), uint2((destCoord + int2(0, 1))));
    uDest.write(float4(coverages.zzz, 1.0), uint2((destCoord + int2(0, 2))));
    uDest.write(float4(coverages.www, 1.0), uint2((destCoord + int2(0, 3))));
}

