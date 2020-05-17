// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bPathTileInfo
{
    int4 iPathTileInfo[1];
};

struct bAlphaTileMap
{
    uint iAlphaTileMap[1];
};

struct bMetadata
{
    uint iMetadata[1];
};

struct bAlphaTiles
{
    int4 iAlphaTiles[1];
};

struct bFills
{
    int4 iFills[1];
};

struct main0_out
{
    float4 oFragColor [[color(0)]];
};

struct main0_in
{
    float2 vFrom [[user(locn0)]];
    float2 vTo [[user(locn1)]];
    uint vPath [[user(locn2)]];
};

fragment main0_out main0(main0_in in [[stage_in]], const device bPathTileInfo& _24 [[buffer(0)]], device bAlphaTileMap& _76 [[buffer(1)]], device bMetadata& _90 [[buffer(2)]], device bAlphaTiles& _97 [[buffer(3)]], device bFills& _112 [[buffer(4)]], float4 gl_FragCoord [[position]])
{
    main0_out out = {};
    int2 tileCoord = int2(gl_FragCoord.xy);
    int4 pathTileRect = _24.iPathTileInfo[(in.vPath * 2u) + 0u];
    uint pathTileStartIndex = uint(_24.iPathTileInfo[(in.vPath * 2u) + 1u].x);
    int2 tileOffset = tileCoord - pathTileRect.xy;
    int pathTileRectWidth = pathTileRect.z - pathTileRect.x;
    uint tileIndex = uint((tileOffset.y * pathTileRectWidth) + tileOffset.x);
    uint globalTileIndex = pathTileStartIndex + tileIndex;
    uint _80 = atomic_fetch_add_explicit((device atomic_uint*)&_76.iAlphaTileMap[globalTileIndex], 1u, memory_order_relaxed);
    uint tileFillIndex = _80;
    if (tileFillIndex == 0u)
    {
        uint _93 = atomic_fetch_add_explicit((device atomic_uint*)&_90.iMetadata[1], 1u, memory_order_relaxed);
        uint alphaTileIndex = _93;
        _97.iAlphaTiles[alphaTileIndex] = int4(tileCoord, int(in.vPath), 0);
    }
    uint _108 = atomic_fetch_add_explicit((device atomic_uint*)&_90.iMetadata[0], 1u, memory_order_relaxed);
    uint fillIndex = _108;
    _112.iFills[(fillIndex * 2u) + 0u] = int4(int2(in.vFrom), int2(in.vTo));
    _112.iFills[(fillIndex * 2u) + 1u] = int4(tileCoord, int(in.vPath), 0);
    out.oFragColor = float4(1.0, 0.0, 0.0, 1.0);
    return out;
}

