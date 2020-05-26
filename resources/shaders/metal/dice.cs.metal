// Automatically generated from files in pathfinder/shaders/. Do not edit!
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"
#pragma clang diagnostic ignored "-Wunused-variable"

#include <metal_stdlib>
#include <simd/simd.h>
#include <metal_atomic>

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
void emitLineSegment(thread const float4& lineSegment, thread const uint& pathIndex, device bComputeIndirectParams& v_37, device bOutputSegments& v_59)
{
    uint _45 = atomic_fetch_add_explicit((device atomic_uint*)&v_37.iComputeIndirectParams[5], 1u, memory_order_relaxed);
    uint outputSegmentIndex = _45;
    if ((outputSegmentIndex % 64u) == 0u)
    {
        uint _53 = atomic_fetch_add_explicit((device atomic_uint*)&v_37.iComputeIndirectParams[0], 1u, memory_order_relaxed);
    }
    v_59.iOutputSegments[outputSegmentIndex].line = lineSegment;
    v_59.iOutputSegments[outputSegmentIndex].pathIndex.x = pathIndex;
}

static inline __attribute__((always_inline))
bool curveIsFlat(thread const float4& baseline, thread const float4& ctrl)
{
    float4 uv = ((float4(3.0) * ctrl) - (float4(2.0) * baseline)) - baseline.zwxy;
    uv *= uv;
    uv = fast::max(uv, uv.zwxy);
    return (uv.x + uv.y) <= 1.0;
}

static inline __attribute__((always_inline))
void subdivideCurve(thread const float4& baseline, thread const float4& ctrl, thread const float& t, thread float4& prevBaseline, thread float4& prevCtrl, thread float4& nextBaseline, thread float4& nextCtrl)
{
    float2 p0 = baseline.xy;
    float2 p1 = ctrl.xy;
    float2 p2 = ctrl.zw;
    float2 p3 = baseline.zw;
    float2 p0p1 = mix(p0, p1, float2(t));
    float2 p1p2 = mix(p1, p2, float2(t));
    float2 p2p3 = mix(p2, p3, float2(t));
    float2 p0p1p2 = mix(p0p1, p1p2, float2(t));
    float2 p1p2p3 = mix(p1p2, p2p3, float2(t));
    float2 p0p1p2p3 = mix(p0p1p2, p1p2p3, float2(t));
    prevBaseline = float4(p0, p0p1p2p3);
    prevCtrl = float4(p0p1, p0p1p2);
    nextBaseline = float4(p0p1p2p3, p3);
    nextCtrl = float4(p1p2p3, p2p3);
}

kernel void main0(device bComputeIndirectParams& v_37 [[buffer(0)]], device bOutputSegments& v_59 [[buffer(1)]], const device bInputIndices& _196 [[buffer(2)]], const device bPoints& _239 [[buffer(3)]], uint3 gl_GlobalInvocationID [[thread_position_in_grid]])
{
    uint inputIndex = gl_GlobalInvocationID.x;
    if (inputIndex >= v_37.iComputeIndirectParams[4])
    {
        return;
    }
    uint2 inputIndices = _196.iInputIndices[inputIndex];
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
    float4 baseline = float4(_239.iPoints[fromPointIndex], _239.iPoints[toPointIndex]);
    if ((flagsPathIndex & 3221225472u) == 0u)
    {
        float4 param = baseline;
        uint param_1 = pathIndex;
        emitLineSegment(param, param_1, v_37, v_59);
        return;
    }
    float2 ctrl0 = _239.iPoints[fromPointIndex + 1u];
    float4 ctrl;
    if ((flagsPathIndex & 2147483648u) != 0u)
    {
        float2 ctrl0_2 = ctrl0 * float2(2.0);
        ctrl = (baseline + (ctrl0 * float2(2.0)).xyxy) * float4(0.3333333432674407958984375);
    }
    else
    {
        ctrl = float4(ctrl0, _239.iPoints[fromPointIndex + 2u]);
    }
    int curveStackSize = 1;
    spvUnsafeArray<float4, 32> baselines;
    baselines[0] = baseline;
    spvUnsafeArray<float4, 32> ctrls;
    ctrls[0] = ctrl;
    float4 param_9;
    float4 param_10;
    float4 param_11;
    float4 param_12;
    while (curveStackSize > 0)
    {
        curveStackSize--;
        baseline = baselines[curveStackSize];
        ctrl = ctrls[curveStackSize];
        float4 param_2 = baseline;
        float4 param_3 = ctrl;
        bool _328 = curveIsFlat(param_2, param_3);
        bool _337;
        if (!_328)
        {
            _337 = (curveStackSize + 2) >= 32;
        }
        else
        {
            _337 = _328;
        }
        if (_337)
        {
            float4 param_4 = baseline;
            uint param_5 = pathIndex;
            emitLineSegment(param_4, param_5, v_37, v_59);
        }
        else
        {
            float4 param_6 = baseline;
            float4 param_7 = ctrl;
            float param_8 = 0.5;
            subdivideCurve(param_6, param_7, param_8, param_9, param_10, param_11, param_12);
            baselines[curveStackSize + 1] = param_9;
            ctrls[curveStackSize + 1] = param_10;
            baselines[curveStackSize + 0] = param_11;
            ctrls[curveStackSize + 0] = param_12;
            curveStackSize += 2;
        }
    }
}

