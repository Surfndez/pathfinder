#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












#extension GL_GOOGLE_include_directive : enable







precision highp float;





layout(local_size_x = 64)in;

struct Segment {
    vec4 line;
    uvec4 pathIndex;
};

layout(std430, binding = 0)buffer bComputeIndirectParams {






    restrict uint iComputeIndirectParams[];
};

layout(std430, binding = 1)buffer bPoints {
    restrict readonly vec2 iPoints[];
};

layout(std430, binding = 2)buffer bInputIndices {
    restrict readonly uvec2 iInputIndices[];
};

layout(std430, binding = 3)buffer bOutputSegments {
    restrict Segment iOutputSegments[];
};

void emitLineSegment(vec4 lineSegment, uint pathIndex){
    uint outputSegmentIndex = atomicAdd(iComputeIndirectParams[5], 1);
    if(outputSegmentIndex % 64 == 0)
        atomicAdd(iComputeIndirectParams[0], 1);

    iOutputSegments[outputSegmentIndex]. line = lineSegment;
    iOutputSegments[outputSegmentIndex]. pathIndex . x = pathIndex;
}

void main(){
    uint inputIndex = gl_GlobalInvocationID . x;
    if(inputIndex >= iComputeIndirectParams[4])
        return;

    uvec2 inputIndices = iInputIndices[inputIndex];
    uint fromPointIndex = inputIndices . x, flagsPathIndex = inputIndices . y;
    uint pathIndex = flagsPathIndex & 0xbfffffffu;

    uint toPointIndex = fromPointIndex;
    if((flagsPathIndex & 0x40000000u)!= 0u)
        toPointIndex += 3;
    else if((flagsPathIndex & 0x80000000u)!= 0u)
        toPointIndex += 2;
    else
        toPointIndex += 1;

    vec4 baseline = vec4(iPoints[fromPointIndex], iPoints[toPointIndex]);
    if((flagsPathIndex &(0x40000000u |
                                                             0x80000000u))== 0){
        emitLineSegment(baseline, pathIndex);
        return;
    }


    vec2 ctrl0 = iPoints[fromPointIndex + 1];
    vec4 ctrl;
    if((flagsPathIndex & 0x80000000u)!= 0){
        vec2 ctrl0_2 = ctrl0 * vec2(2.0);
        ctrl =(baseline +(ctrl0 * vec2(2.0)). xyxy)* vec4(1.0 / 3.0);
    } else {
        ctrl = vec4(ctrl0, iPoints[fromPointIndex + 2]);
    }


    emitLineSegment(vec4(baseline . xy, ctrl . xy), pathIndex);
    emitLineSegment(ctrl, pathIndex);
    emitLineSegment(vec4(ctrl . zw, baseline . zw), pathIndex);
}

