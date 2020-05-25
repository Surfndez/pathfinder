// Automatically generated from files in pathfinder/shaders/. Do not edit!
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Segment
{
    float4 line;
    uint4 pathIndex;
};

struct bSegments
{
    Segment iSegments[1];
};

struct main0_out
{
    float2 vFrom [[user(locn0)]];
    float2 vTo [[user(locn1)]];
    uint vPathIndex [[user(locn2)]];
    float4 gl_Position [[position]];
};

vertex main0_out main0(constant int2& uFramebufferSize [[buffer(1)]], const device bSegments& _47 [[buffer(0)]], uint gl_VertexID [[vertex_id]])
{
    main0_out out = {};
    uint segmentIndex = uint(gl_VertexID) / 6u;
    float2 tessCoord;
    switch (gl_VertexID % 6)
    {
        case 0:
        {
            tessCoord = float2(0.0);
            break;
        }
        case 1:
        case 3:
        {
            tessCoord = float2(1.0, 0.0);
            break;
        }
        case 2:
        case 5:
        {
            tessCoord = float2(0.0, 1.0);
            break;
        }
        case 4:
        {
            tessCoord = float2(1.0);
            break;
        }
    }
    float4 line = _47.iSegments[segmentIndex].line;
    uint pathIndex = _47.iSegments[segmentIndex].pathIndex.x;
    float2 from = line.xy / float2(16.0);
    float2 to = line.zw / float2(16.0);
    float2 vector = normalize(to - from) * float2(0.5);
    float2 normal = float2(-vector.y, vector.x);
    float2 tilePosition = mix(from - vector, to + vector, float2(tessCoord.y)) + mix(-normal, normal, float2(tessCoord.x));
    out.vFrom = from;
    out.vTo = to;
    out.vPathIndex = pathIndex;
    out.gl_Position = float4(mix(float2(-1.0), float2(1.0), tilePosition / float2(uFramebufferSize)), 0.0, 1.0);
    return out;
}

