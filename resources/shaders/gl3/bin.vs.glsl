#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;





uniform ivec2 uFramebufferSize;

in ivec2 aTessCoord;
in vec2 aFrom;
in vec2 aTo;
in int aPathIndex;

out vec2 vFrom;
out vec2 vTo;
flat out uint vPathIndex;

void main(){
    vec2 vector = normalize(aTo - aFrom);
    vec2 normal = vec2(- vector . y, vector . x);
    vec2 tessCoord = vec2(aTessCoord);
    vec2 tilePosition = mix(aFrom / vec2(16.0)- vector, aTo / vec2(16.0)+ vector, tessCoord . y)+
        mix(- normal, normal, tessCoord . x);

    vFrom = aFrom / vec2(16.0);
    vTo = aTo / vec2(16.0);
    vPathIndex = uint(aPathIndex);

    gl_Position = vec4(mix(vec2(- 1.0), vec2(1.0), tilePosition / uFramebufferSize), 0.0, 1.0);
}

