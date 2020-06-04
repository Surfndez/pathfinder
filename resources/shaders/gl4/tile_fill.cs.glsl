#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












#extension GL_GOOGLE_include_directive : enable

precision highp float;





layout(local_size_x = 16, local_size_y = 4)in;

uniform writeonly image2D uDest;
uniform sampler2D uAreaLUT;
uniform ivec2 uFramebufferTileSize;
uniform sampler2D uTextureMetadata;
uniform ivec2 uTextureMetadataSize;












vec4 computeCoverage(vec2 from, vec2 to, sampler2D areaLUT){

    vec2 left = from . x < to . x ? from : to, right = from . x < to . x ? to : from;


    vec2 window = clamp(vec2(from . x, to . x), - 0.5, 0.5);
    float offset = mix(window . x, window . y, 0.5)- left . x;
    float t = offset /(right . x - left . x);


    float y = mix(left . y, right . y, t);
    float d =(right . y - left . y)/(right . x - left . x);


    float dX = window . x - window . y;
    return texture(areaLUT, vec2(y + 8.0, abs(d * dX))/ 16.0)* dX;
}


layout(std430, binding = 0)buffer bFills {
    restrict readonly uint iFills[];
};

layout(std430, binding = 1)buffer bTileLinkMap {
    restrict readonly ivec2 iTileLinkMap[];
};

layout(std430, binding = 2)buffer bTiles {
    restrict readonly int iTiles[];
};

layout(std430, binding = 3)buffer bInitialTileMap {
    restrict readonly uint iInitialTileMap[];
};





























void main(){
    ivec2 tileSubCoord = ivec2(gl_LocalInvocationID . xy)* ivec2(1, 4);
    ivec2 tileCoord = ivec2(gl_WorkGroupID . xy);

    vec4 colors[4]= { vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)};
    uint tileIndexOffset = tileCoord . x + tileCoord . y * uFramebufferTileSize . x;
    int tileIndex = int(iInitialTileMap[tileIndexOffset]);
    uint iteration = 0;

    while(tileIndex >= 0){
        uint pathIndex = uint(iTiles[tileIndex * 4 + 2]);
        uint colorIndex = uint(iTiles[tileIndex * 4 + 3])& 0xffff;
        int backdrop = iTiles[tileIndex * 4 + 3]>> 24;

        vec4 coverages = vec4(backdrop);
        int fillIndex = iTileLinkMap[tileIndex]. x;
        while(fillIndex >= 0){
            uint fillFrom = iFills[fillIndex * 3 + 0], fillTo = iFills[fillIndex * 3 + 1];
            vec4 lineSegment = vec4(fillFrom & 0xffff, fillFrom >> 16,
                                    fillTo & 0xffff, fillTo >> 16)/ 256.0;

            coverages += computeCoverage(lineSegment . xy -(vec2(tileSubCoord)+ vec2(0.5)),
                                         lineSegment . zw -(vec2(tileSubCoord)+ vec2(0.5)),
                                         uAreaLUT);

            fillIndex = int(iFills[fillIndex * 3 + 2]);

            iteration ++;
            if(iteration >= 16384)
                return;
        }

        vec2 textureMetadataScale = vec2(1.0)/ vec2(uTextureMetadataSize);
        vec2 metadataEntryCoord = vec2(colorIndex % 128 * 4, colorIndex / 128);
        vec2 colorTexMatrix0Coord =(metadataEntryCoord + vec2(0.5, 0.5))* textureMetadataScale;
        vec2 colorTexOffsetsCoord =(metadataEntryCoord + vec2(1.5, 0.5))* textureMetadataScale;
        vec2 baseColorCoord =(metadataEntryCoord + vec2(2.5, 0.5))* textureMetadataScale;
        vec4 colorTexMatrix0 = texture(uTextureMetadata, colorTexMatrix0Coord);
        vec4 colorTexOffsets = texture(uTextureMetadata, colorTexOffsetsCoord);
        vec4 baseColor = texture(uTextureMetadata, baseColorCoord);

        for(uint y = 0;y < 4;y ++){
            vec4 thisColor = vec4(baseColor . rgb, baseColor . a * clamp(abs(coverages[y]), 0.0, 1.0));
            colors[y]= mix(colors[y], thisColor, thisColor . a);
        }

        tileIndex = iTileLinkMap[tileIndex]. y;
    }

    ivec2 destCoord = tileCoord * ivec2(16)+ tileSubCoord;
    for(uint y = 0;y < 4;y ++)
        imageStore(uDest, destCoord + ivec2(0, y), colors[y]);
}

