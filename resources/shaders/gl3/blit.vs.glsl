#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;

in ivec2 aPosition;

out vec2 vTexCoord;

void main(){
    vTexCoord = vec2(aPosition);
    gl_Position = vec4(mix(vec2(- 1.0), vec2(1.0), vec2(aPosition)), 0.0, 1.0);
}

