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

struct bFills
{
    uint iFills[1];
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
bool computeTileIndex(thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset, thread uint& outTileIndex)
{
    int2 offsetCoords = tileCoords - pathTileRect.xy;
    outTileIndex = (pathTileOffset + uint(offsetCoords.x)) + uint(offsetCoords.y * (pathTileRect.z - pathTileRect.x));
    return all(bool4(tileCoords >= pathTileRect.xy, tileCoords < pathTileRect.zw));
}

static inline __attribute__((always_inline))
void addFill(thread const float4& lineSegment, thread const int2& tileCoords, thread const int4& pathTileRect, thread const uint& pathTileOffset, device bTiles& v_105, device bIndirectDrawParams& v_125, device bFills& v_137)
{
    int2 param = tileCoords;
    int4 param_1 = pathTileRect;
    uint param_2 = pathTileOffset;
    uint param_3;
    bool _81 = computeTileIndex(param, param_1, param_2, param_3);
    uint tileIndex = param_3;
    if (!_81)
    {
        return;
    }
    uint4 scaledLocalLine = uint4((lineSegment - float4(tileCoords.xyxy * int4(16))) * float4(256.0));
    uint _114;
    do
    {
        _114 = 4294967295u;
    } while (!atomic_compare_exchange_weak_explicit((device atomic_uint*)&v_105.iTiles[(tileIndex * 4u) + 1u], &_114, 0u, memory_order_relaxed, memory_order_relaxed) && _114 == 4294967295u);
    if (_114 == 4294967295u)
    {
        uint _128 = atomic_fetch_add_explicit((device atomic_uint*)&v_125.iIndirectDrawParams[4], 1u, memory_order_relaxed);
        uint _129 = atomic_exchange_explicit((device atomic_uint*)&v_105.iTiles[(tileIndex * 4u) + 1u], _128, memory_order_relaxed);
    }
    uint _133 = atomic_fetch_add_explicit((device atomic_uint*)&v_125.iIndirectDrawParams[1], 1u, memory_order_relaxed);
    uint fillIndex = _133;
    v_137.iFills[(fillIndex * 3u) + 0u] = scaledLocalLine.x | (scaledLocalLine.y << uint(16));
    v_137.iFills[(fillIndex * 3u) + 1u] = scaledLocalLine.z | (scaledLocalLine.w << uint(16));
    v_137.iFills[(fillIndex * 3u) + 2u] = tileIndex;
}

kernel void main0(device bTiles& v_105 [[buffer(0)]], device bIndirectDrawParams& v_125 [[buffer(1)]], device bFills& v_137 [[buffer(2)]], const device bSegments& _176 [[buffer(3)]], const device bMetadata& _189 [[buffer(4)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint segmentIndex = gl_GlobalInvocationID.x;
    float4 lineSegment = _176.iSegments[segmentIndex].line;
    uint pathIndex = _176.iSegments[segmentIndex].pathIndex.x;
    int4 pathTileRect = _189.iMetadata[(pathIndex * 2u) + 0u];
    uint pathTileOffset = uint(_189.iMetadata[(pathIndex * 2u) + 1u].x);
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
    float _323;
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
            _323 = tMax.x;
        }
        else
        {
            _323 = tMax.y;
        }
        float nextT = fast::min(_323, 1.0);
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
        addFill(param, param_1, param_2, param_3, v_105, v_125, v_137);
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
            addFill(param_4, param_5, param_6, param_7, v_105, v_125, v_137);
        }
        int backdropAdjustment = 0;
        if ((tileStep.x < 0) && (lastStepDirection == 1))
        {
            backdropAdjustment = 1;
        }
        else
        {
            if ((tileStep.x > 0) && (nextStepDirection == 1))
            {
                backdropAdjustment = -1;
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

