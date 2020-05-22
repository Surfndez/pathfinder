#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!












precision highp float;








uniform sampler2D uSrc;

in vec2 vTexCoord0;
in float vBackdrop0;
in vec2 vTexCoord1;
in float vBackdrop1;
flat in uint vCtrl;

out vec4 oFragColor;

void main(){
    vec4 texColor0 = vec4(0.0), texColor1 = vec4(0.0);
    if((vCtrl & 0x1u)!= 0u)
        texColor0 = texture(uSrc, vTexCoord0);
    if((vCtrl & 0x2u)!= 0u)
        texColor1 = texture(uSrc, vTexCoord1);
    oFragColor = min(abs(texColor0 + vBackdrop0), abs(texColor1 + vBackdrop1));
}

