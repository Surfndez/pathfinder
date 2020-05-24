#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;











uniform ivec2 uFramebufferSize;

layout(std430, binding = 0)buffer bMetadata {
    restrict readonly ivec4 iMetadata[];
};






layout(std430, binding = 1)buffer bIndirectDrawParams {
    restrict uint iIndirectDrawParams[];
};

layout(std430, binding = 2)buffer bFills {
    restrict writeonly uint iFills[];
};

layout(std430, binding = 3)buffer bTiles {
    restrict uint iTiles[];
};

in vec2 vFrom;
in vec2 vTo;
flat in uint vPathIndex;

out vec4 oFragColor;



uint computeOutcode(vec2 p, vec4 rect){
    uint code = 0x0u;
    if(p . x < rect . x)
        code |= 0x1u;
    else if(p . x > rect . z)
        code |= 0x2u;
    if(p . y < rect . y)
        code |= 0x8u;
    else if(p . y > rect . w)
        code |= 0x4u;
    return code;
}

bool clipLine(vec4 line, vec4 rect, out vec4 outLine){
    uvec2 outcodes = uvec2(computeOutcode(line . xy, rect), computeOutcode(line . zw, rect));
    while(true){
        if((outcodes . x | outcodes . y)== 0u){
            outLine = line;
            return true;
        }
        if((outcodes . x & outcodes . y)!= 0u){
            outLine = line;
            return false;
        }

        uint outcode = max(outcodes . x, outcodes . y);
        vec2 p;
        if((outcode & 0x8u)!= 0u)
            p = vec2(mix(line . x, line . z,(rect . y - line . y)/(line . w - line . y)), rect . y);
        else if((outcode & 0x4u)!= 0u)
            p = vec2(mix(line . x, line . z,(rect . w - line . y)/(line . w - line . y)), rect . w);
        else if((outcode & 0x1u)!= 0u)
            p = vec2(rect . x, mix(line . y, line . w,(rect . x - line . x)/(line . z - line . x)));
        else if((outcode & 0x2u)!= 0u)
            p = vec2(rect . z, mix(line . y, line . w,(rect . z - line . x)/(line . z - line . x)));

        if(outcode == outcodes . x){
            line . xy = p;
            outcodes . x = computeOutcode(line . xy, rect);
        } else {
            line . zw = p;
            outcodes . y = computeOutcode(line . zw, rect);
        }
    }
}

void main(){
    vec2 fragCoord = gl_FragCoord . xy;




    ivec2 tileCoord = ivec2(fragCoord);
    vec4 tileRect = fragCoord . xyxy + vec4(vec2(- 0.5), vec2(0.5));
    vec4 line;
    bool inBounds = clipLine(vec4(vFrom, vTo), tileRect, line);

    if(inBounds){
        ivec4 pathTileRect = iMetadata[vPathIndex * 2 + 0];
        uint pathTileOffset = uint(iMetadata[vPathIndex * 2 + 1]. x);

        ivec2 tileOffset = tileCoord - pathTileRect . xy;
        uint tileIndex = pathTileOffset +
            uint(tileOffset . y *(pathTileRect . z - pathTileRect . x)+ tileOffset . x);



        uint alphaTileIndex = atomicAdd(iTiles[tileIndex * 4 + 1], 0);
        if(alphaTileIndex == 0){
            uint trialAlphaTileIndex = atomicAdd(iIndirectDrawParams[4], 1);
            alphaTileIndex = atomicCompSwap(iTiles[tileIndex * 4 + 1], 0, trialAlphaTileIndex);
            if(alphaTileIndex == 0){

                alphaTileIndex = trialAlphaTileIndex;
                iTiles[tileIndex * 4 + 1]= alphaTileIndex;
            }
        }

        vec4 localLine = line - tileRect . xyxy;
        uvec4 scaledLocalLine = uvec4(localLine * vec4(256.0));


        uint fillIndex = atomicAdd(iIndirectDrawParams[1], 1);


        iFills[fillIndex * 3 + 0]= scaledLocalLine . x |(scaledLocalLine . y << 16);
        iFills[fillIndex * 3 + 1]= scaledLocalLine . z |(scaledLocalLine . w << 16);
        iFills[fillIndex * 3 + 2]= alphaTileIndex;
    }


    oFragColor = vec4(1.0, 0.0, 0.0, 1.0);
}

