// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bTiles
{
    uint iTiles[1];
};

struct bIndirectDrawParams
{
    uint iIndirectDrawParams[1];
};

struct bTileLinkMap
{
    uint iTileLinkMap[1];
};

struct bFills
{
    uint iFills[1];
};

struct bBackdrops
{
    uint iBackdrops[1];
};

struct Segment
{
    float4 line;
    uint4 pathIndex;
};

struct bSegments
{
    Segment iSegments[1];
};

struct bMetadata
{
    int4 iMetadata[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(64u, 1u, 1u);

static inline __attribute__((always_inline))
uint computeTileIndexNoCheck(thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset)
{
    int2 offsetCoords = tileCoords - pathTileRect.xy;
    return (pathTileOffset + uint(offsetCoords.x)) + uint(offsetCoords.y * (pathTileRect.z - pathTileRect.x));
}

static inline __attribute__((always_inline))
bool4 computeTileOutcodes(thread const int2& tileCoords, thread const int4& pathTileRect)
{
    return bool4(tileCoords < pathTileRect.xy, tileCoords >= pathTileRect.zw);
}

static inline __attribute__((always_inline))
bool computeTileIndex(thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset, thread uint& outTileIndex)
{
    int2 param = tileCoords;
    int4 param_1 = pathTileRect;
    uint param_2 = pathTileOffset;
    outTileIndex = computeTileIndexNoCheck(param, param_1, param_2);
    int2 param_3 = tileCoords;
    int4 param_4 = pathTileRect;
    return !any(computeTileOutcodes(param_3, param_4));
}

static inline __attribute__((always_inline))
void addFill(thread const float4& lineSegment, thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset, device bTiles& v_149, device bIndirectDrawParams& v_169, thread int uFillInComputeEnabled, device bTileLinkMap& v_188, device bFills& v_199)
{
    int2 param = tileCoords;
    int4 param_1 = pathTileRect;
    uint param_2 = pathTileOffset;
    uint param_3;
    bool _117 = computeTileIndex(param, param_1, param_2, param_3);
    uint tileIndex = param_3;
    if (!_117)
    {
        return;
    }
    uint4 scaledLocalLine = uint4((lineSegment - float4(tileCoords.xyxy * int4(16))) * float4(256.0));
    if (scaledLocalLine.x == scaledLocalLine.z)
    {
        return;
    }
    uint _158;
    do
    {
        _158 = 4294967295u;
    } while (!atomic_compare_exchange_weak_explicit((device atomic_uint*)&v_149.iTiles[(tileIndex * 4u) + 1u], &_158, 0u, memory_order_relaxed, memory_order_relaxed) && _158 == 4294967295u);
    if (_158 == 4294967295u)
    {
        uint _172 = atomic_fetch_add_explicit((device atomic_uint*)&v_169.iIndirectDrawParams[4], 1u, memory_order_relaxed);
        uint _173 = atomic_exchange_explicit((device atomic_uint*)&v_149.iTiles[(tileIndex * 4u) + 1u], _172, memory_order_relaxed);
    }
    uint _177 = atomic_fetch_add_explicit((device atomic_uint*)&v_169.iIndirectDrawParams[1], 1u, memory_order_relaxed);
    uint fillIndex = _177;
    uint fillLink;
    if (uFillInComputeEnabled != 0)
    {
        uint _193 = atomic_exchange_explicit((device atomic_uint*)&v_188.iTileLinkMap[tileIndex * 2u], fillIndex, memory_order_relaxed);
        fillLink = _193;
    }
    else
    {
        fillLink = tileIndex;
    }
    v_199.iFills[(fillIndex * 3u) + 0u] = scaledLocalLine.x | (scaledLocalLine.y << uint(16));
    v_199.iFills[(fillIndex * 3u) + 1u] = scaledLocalLine.z | (scaledLocalLine.w << uint(16));
    v_199.iFills[(fillIndex * 3u) + 2u] = fillLink;
}

static inline __attribute__((always_inline))
void adjustBackdrop(thread const int& backdropDelta, thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset, thread const uint& pathBackdropOffset, device bTiles& v_149, device bBackdrops& v_264)
{
    int2 param = tileCoords;
    int4 param_1 = pathTileRect;
    bool4 outcodes = computeTileOutcodes(param, param_1);
    if (any(outcodes))
    {
        bool _243 = (!outcodes.x) && outcodes.y;
        bool _249;
        if (_243)
        {
            _249 = !outcodes.z;
        }
        else
        {
            _249 = _243;
        }
        if (_249)
        {
            uint backdropIndex = pathBackdropOffset + uint(tileCoords.x - pathTileRect.x);
            uint _270 = atomic_fetch_add_explicit((device atomic_uint*)&v_264.iBackdrops[backdropIndex * 3u], uint(backdropDelta), memory_order_relaxed);
        }
    }
    else
    {
        int2 param_2 = tileCoords;
        int4 param_3 = pathTileRect;
        uint param_4 = pathTileOffset;
        uint tileIndex = computeTileIndexNoCheck(param_2, param_3, param_4);
        uint _288 = atomic_fetch_add_explicit((device atomic_uint*)&v_149.iTiles[(tileIndex * 4u) + 3u], uint(backdropDelta << 24), memory_order_relaxed);
    }
}

kernel void main0(constant int& uFillInComputeEnabled [[buffer(2)]], device bTiles& v_149 [[buffer(0)]], device bIndirectDrawParams& v_169 [[buffer(1)]], device bTileLinkMap& v_188 [[buffer(3)]], device bFills& v_199 [[buffer(4)]], device bBackdrops& v_264 [[buffer(5)]], const device bSegments& _309 [[buffer(6)]], const device bMetadata& _322 [[buffer(7)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint segmentIndex = gl_GlobalInvocationID.x;
    if (segmentIndex >= v_169.iIndirectDrawParams[5])
    {
        return;
    }
    float4 lineSegment = _309.iSegments[segmentIndex].line;
    uint pathIndex = _309.iSegments[segmentIndex].pathIndex.x;
    int4 pathTileRect = _322.iMetadata[(pathIndex * 3u) + 0u];
    uint pathTileOffset = uint(_322.iMetadata[(pathIndex * 3u) + 1u].x);
    uint pathBackdropOffset = uint(_322.iMetadata[(pathIndex * 3u) + 2u].x);
    int2 tileSize = int2(16);
    int4 tileLineSegment = int4(floor(lineSegment / float4(tileSize.xyxy)));
    int2 fromTileCoords = tileLineSegment.xy;
    int2 toTileCoords = tileLineSegment.zw;
    float2 vector = lineSegment.zw - lineSegment.xy;
    float2 vectorIsNegative = float2((vector.x < 0.0) ? (-1.0) : 0.0, (vector.y < 0.0) ? (-1.0) : 0.0);
    int2 tileStep = int2((vector.x < 0.0) ? (-1) : 1, (vector.y < 0.0) ? (-1) : 1);
    float2 firstTileCrossing = float2((fromTileCoords + int2(int(vector.x >= 0.0), int(vector.y >= 0.0))) * tileSize);
    float2 tMax = (firstTileCrossing - lineSegment.xy) / vector;
    float2 tDelta = abs(float2(tileSize) / vector);
    float2 currentPosition = lineSegment.xy;
    int2 tileCoords = fromTileCoords;
    int lastStepDirection = 0;
    uint iteration = 0u;
    int nextStepDirection;
    float _463;
    float4 auxiliarySegment;
    while (iteration < 1024u)
    {
        if (tMax.x < tMax.y)
        {
            nextStepDirection = 1;
        }
        else
        {
            if (tMax.x > tMax.y)
            {
                nextStepDirection = 2;
            }
            else
            {
                if (float(tileStep.x) > 0.0)
                {
                    nextStepDirection = 1;
                }
                else
                {
                    nextStepDirection = 2;
                }
            }
        }
        if (nextStepDirection == 1)
        {
            _463 = tMax.x;
        }
        else
        {
            _463 = tMax.y;
        }
        float nextT = fast::min(_463, 1.0);
        if (all(tileCoords == toTileCoords))
        {
            nextStepDirection = 0;
        }
        float2 nextPosition = mix(lineSegment.xy, lineSegment.zw, float2(nextT));
        float4 clippedLineSegment = float4(currentPosition, nextPosition);
        float4 param = clippedLineSegment;
        int2 param_1 = tileCoords;
        int4 param_2 = pathTileRect;
        uint param_3 = pathTileOffset;
        addFill(param, param_1, param_2, param_3, v_149, v_169, uFillInComputeEnabled, v_188, v_199);
        bool haveAuxiliarySegment = false;
        if ((tileStep.y < 0) && (nextStepDirection == 2))
        {
            auxiliarySegment = float4(clippedLineSegment.zw, float2(tileCoords * tileSize));
            haveAuxiliarySegment = true;
        }
        else
        {
            if ((tileStep.y > 0) && (lastStepDirection == 2))
            {
                auxiliarySegment = float4(float2(tileCoords * tileSize), clippedLineSegment.xy);
                haveAuxiliarySegment = true;
            }
        }
        if (haveAuxiliarySegment)
        {
            float4 param_4 = auxiliarySegment;
            int2 param_5 = tileCoords;
            int4 param_6 = pathTileRect;
            uint param_7 = pathTileOffset;
            addFill(param_4, param_5, param_6, param_7, v_149, v_169, uFillInComputeEnabled, v_188, v_199);
        }
        if ((tileStep.x < 0) && (lastStepDirection == 1))
        {
            int param_8 = 1;
            int2 param_9 = tileCoords;
            int4 param_10 = pathTileRect;
            uint param_11 = pathTileOffset;
            uint param_12 = pathBackdropOffset;
            adjustBackdrop(param_8, param_9, param_10, param_11, param_12, v_149, v_264);
        }
        else
        {
            if ((tileStep.x > 0) && (nextStepDirection == 1))
            {
                int param_13 = -1;
                int2 param_14 = tileCoords;
                int4 param_15 = pathTileRect;
                uint param_16 = pathTileOffset;
                uint param_17 = pathBackdropOffset;
                adjustBackdrop(param_13, param_14, param_15, param_16, param_17, v_149, v_264);
            }
        }
        if (nextStepDirection == 1)
        {
            tMax.x += tDelta.x;
            tileCoords.x += tileStep.x;
        }
        else
        {
            if (nextStepDirection == 2)
            {
                tMax.y += tDelta.y;
                tileCoords.y += tileStep.y;
            }
            else
            {
                if (nextStepDirection == 0)
                {
                    break;
                }
            }
        }
        currentPosition = nextPosition;
        lastStepDirection = nextStepDirection;
        iteration++;
    }
}

