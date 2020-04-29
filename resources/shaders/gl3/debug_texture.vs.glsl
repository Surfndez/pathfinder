#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;
precision highp sampler2D;

uniform vec2 uFramebufferSize;
uniform vec2 uTextureSize;

in ivec2 aPosition;
in ivec2 aTexCoord;



void main(){

    vec2 position = vec2(aTexCoord)* uTextureSize;
    position = vec2(aPosition)/ uFramebufferSize * 2.0 - 1.0;
    gl_Position = vec4(position . x, - position . y, 0.0, 1.0);
}

