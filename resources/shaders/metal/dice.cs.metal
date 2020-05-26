// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

using namespace metal;

struct bComputeIndirectParams
{
    uint iComputeIndirectParams[1];
};

struct Segment
{
    float4 line;
    uint4 pathIndex;
};

struct bOutputSegments
{
    Segment iOutputSegments[1];
};

struct bInputIndices
{
    uint2 iInputIndices[1];
};

struct bPoints
{
    float2 iPoints[1];
};

constant uint3 gl_WorkGroupSize [[maybe_unused]] = uint3(64u, 1u, 1u);

static inline __attribute__((always_inline))
void emitLineSegment(thread const float4& lineSegment, thread const uint& pathIndex, device bComputeIndirectParams& v_20, device bOutputSegments& v_43)
{
    uint _28 = atomic_fetch_add_explicit((device atomic_uint*)&v_20.iComputeIndirectParams[5], 1u, memory_order_relaxed);
    uint outputSegmentIndex = _28;
    if ((outputSegmentIndex % 64u) == 0u)
    {
        uint _37 = atomic_fetch_add_explicit((device atomic_uint*)&v_20.iComputeIndirectParams[0], 1u, memory_order_relaxed);
    }
    v_43.iOutputSegments[outputSegmentIndex].line = lineSegment;
    v_43.iOutputSegments[outputSegmentIndex].pathIndex.x = pathIndex;
}

kernel void main0(device bComputeIndirectParams& v_20 [[buffer(0)]], device bOutputSegments& v_43 [[buffer(1)]], const device bInputIndices& _73 [[buffer(2)]], const device bPoints& _117 [[buffer(3)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint inputIndex = gl_GlobalInvocationID.x;
    if (inputIndex >= v_20.iComputeIndirectParams[4])
    {
        return;
    }
    uint2 inputIndices = _73.iInputIndices[inputIndex];
    uint fromPointIndex = inputIndices.x;
    uint flagsPathIndex = inputIndices.y;
    uint pathIndex = flagsPathIndex & 3221225471u;
    uint toPointIndex = fromPointIndex;
    if ((flagsPathIndex & 1073741824u) != 0u)
    {
        toPointIndex += 3u;
    }
    else
    {
        if ((flagsPathIndex & 2147483648u) != 0u)
        {
            toPointIndex += 2u;
        }
        else
        {
            toPointIndex++;
        }
    }
    float4 baseline = float4(_117.iPoints[fromPointIndex], _117.iPoints[toPointIndex]);
    if ((flagsPathIndex & 3221225472u) == 0u)
    {
        float4 param = baseline;
        uint param_1 = pathIndex;
        emitLineSegment(param, param_1, v_20, v_43);
        return;
    }
    float2 ctrl0 = _117.iPoints[fromPointIndex + 1u];
    float4 ctrl;
    if ((flagsPathIndex & 2147483648u) != 0u)
    {
        float2 ctrl0_2 = ctrl0 * float2(2.0);
        ctrl = (baseline + (ctrl0 * float2(2.0)).xyxy) * float4(0.3333333432674407958984375);
    }
    else
    {
        ctrl = float4(ctrl0, _117.iPoints[fromPointIndex + 2u]);
    }
    float4 param_2 = float4(baseline.xy, ctrl.xy);
    uint param_3 = pathIndex;
    emitLineSegment(param_2, param_3, v_20, v_43);
    float4 param_4 = ctrl;
    uint param_5 = pathIndex;
    emitLineSegment(param_4, param_5, v_20, v_43);
    float4 param_6 = float4(ctrl.zw, baseline.zw);
    uint param_7 = pathIndex;
    emitLineSegment(param_6, param_7, v_20, v_43);
}

