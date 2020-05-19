#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;





uniform ivec2 uBufferSize;

layout(std430, binding = 0)buffer bBuffer {
    restrict int iBuffer[];
};

in vec2 vTexCoord;

out ivec4 oFragColor;

void main(){
    ivec2 texCoord = ivec2(floor(vTexCoord));
    oFragColor = ivec4(iBuffer[texCoord . y * uBufferSize . x + texCoord . x]);
}

