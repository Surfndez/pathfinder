#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












#extension GL_GOOGLE_include_directive : enable







precision highp float;





layout(local_size_x = 64)in;

struct Segment {
    vec4 line;
    uvec4 pathIndex;
};

layout(std430, binding = 0)buffer bSegments {
    restrict readonly Segment iSegments[];
};

layout(std430, binding = 1)buffer bMetadata {
    restrict readonly ivec4 iMetadata[];
};






layout(std430, binding = 2)buffer bIndirectDrawParams {
    restrict uint iIndirectDrawParams[];
};

layout(std430, binding = 3)buffer bFills {
    restrict writeonly uint iFills[];
};

layout(std430, binding = 4)buffer bTiles {
    restrict uint iTiles[];
};

bool computeTileIndex(ivec2 tileCoords,
                      ivec4 pathTileRect,
                      uint pathTileOffset,
                      out uint outTileIndex){
    ivec2 offsetCoords = tileCoords - pathTileRect . xy;
    outTileIndex = pathTileOffset + offsetCoords . x +
        offsetCoords . y *(pathTileRect . z - pathTileRect . x);
    return all(bvec4(greaterThanEqual(tileCoords, pathTileRect . xy),
                     lessThan(tileCoords, pathTileRect . zw)));
}

void addFill(vec4 lineSegment, ivec2 tileCoords, ivec4 pathTileRect, uint pathTileOffset){

    uint tileIndex;
    if(! computeTileIndex(tileCoords, pathTileRect, pathTileOffset, tileIndex))
        return;


    uvec4 scaledLocalLine = uvec4((lineSegment - vec4(tileCoords . xyxy * ivec4(16)))* vec4(256.0));


    if(atomicCompSwap(iTiles[tileIndex * 4 + 1], uint(- 1), 0u)== uint(- 1))
        atomicExchange(iTiles[tileIndex * 4 + 1], atomicAdd(iIndirectDrawParams[4], 1));


    uint fillIndex = atomicAdd(iIndirectDrawParams[1], 1);


    iFills[fillIndex * 3 + 0]= scaledLocalLine . x |(scaledLocalLine . y << 16);
    iFills[fillIndex * 3 + 1]= scaledLocalLine . z |(scaledLocalLine . w << 16);
    iFills[fillIndex * 3 + 2]= tileIndex;
}

void main(){
    uint segmentIndex = gl_GlobalInvocationID . x;
    vec4 lineSegment = iSegments[segmentIndex]. line;
    uint pathIndex = iSegments[segmentIndex]. pathIndex . x;

    ivec4 pathTileRect = iMetadata[pathIndex * 2 + 0];
    uint pathTileOffset = uint(iMetadata[pathIndex * 2 + 1]. x);



    ivec2 tileSize = ivec2(16);

    ivec4 tileLineSegment = ivec4(floor(lineSegment / vec4(tileSize . xyxy)));
    ivec2 fromTileCoords = tileLineSegment . xy, toTileCoords = tileLineSegment . zw;

    vec2 vector = lineSegment . zw - lineSegment . xy;
    vec2 vectorIsNegative = vec2(vector . x < 0.0 ? - 1.0 : 0.0, vector . y < 0.0 ? - 1.0 : 0.0);
    ivec2 tileStep = ivec2(vector . x < 0.0 ? - 1 : 1, vector . y < 0.0 ? - 1 : 1);

    vec2 firstTileCrossing = vec2((fromTileCoords + ivec2(vector . x >= 0.0 ? 1 : 0,
                                                          vector . y >= 0.0 ? 1 : 0))* tileSize);

    vec2 tMax =(firstTileCrossing - lineSegment . xy)/ vector;
    vec2 tDelta = abs(tileSize / vector);

    vec2 currentPosition = lineSegment . xy;
    ivec2 tileCoords = fromTileCoords;
    int lastStepDirection = 0;
    uint iteration = 0;

    while(iteration < 1024u){
        int nextStepDirection;
        if(tMax . x < tMax . y)
            nextStepDirection = 1;
        else if(tMax . x > tMax . y)
            nextStepDirection = 2;
        else if(tileStep . x > 0.0)
            nextStepDirection = 1;
        else
            nextStepDirection = 2;

        float nextT = min(nextStepDirection == 1 ? tMax . x : tMax . y, 1.0);


        if(tileCoords == toTileCoords)
            nextStepDirection = 0;

        vec2 nextPosition = mix(lineSegment . xy, lineSegment . zw, nextT);
        vec4 clippedLineSegment = vec4(currentPosition, nextPosition);
        addFill(clippedLineSegment, tileCoords, pathTileRect, pathTileOffset);


        vec4 auxiliarySegment;
        bool haveAuxiliarySegment = false;
        if(tileStep . y < 0 && nextStepDirection == 2){
            auxiliarySegment = vec4(clippedLineSegment . zw, vec2(tileCoords * tileSize));
            haveAuxiliarySegment = true;
        } else if(tileStep . y > 0 && lastStepDirection == 2){
            auxiliarySegment = vec4(vec2(tileCoords * tileSize), clippedLineSegment . xy);
            haveAuxiliarySegment = true;
        }
        if(haveAuxiliarySegment)
            addFill(auxiliarySegment, tileCoords, pathTileRect, pathTileOffset);


        int backdropAdjustment = 0;
        if(tileStep . x < 0 && lastStepDirection == 1)
            backdropAdjustment = 1;
        else if(tileStep . x > 0 && nextStepDirection == 1)
            backdropAdjustment = - 1;



        if(nextStepDirection == 1){
            tMax . x += tDelta . x;
            tileCoords . x += tileStep . x;
        } else if(nextStepDirection == 2){
            tMax . y += tDelta . y;
            tileCoords . y += tileStep . y;
        } else if(nextStepDirection == 0){
            break;
        }

        currentPosition = nextPosition;
        lastStepDirection = nextStepDirection;

        iteration ++;
    }
}

