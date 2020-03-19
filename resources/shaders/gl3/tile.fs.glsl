#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!

































#extension GL_GOOGLE_include_directive : enable

precision highp float;

















































uniform sampler2D uDestTexture;
uniform sampler2D uColorTexture0;
uniform sampler2D uColorTexture1;
uniform sampler2D uMaskTexture0;
uniform sampler2D uMaskTexture1;
uniform sampler2D uGammaLUT;
uniform vec4 uFilterParams0;
uniform vec4 uFilterParams1;
uniform vec2 uDestTextureSize;
uniform int uCtrl;

in vec3 vMaskTexCoord0;
in vec3 vMaskTexCoord1;
in vec2 vColorTexCoord0;
in vec2 vColorTexCoord1;

out vec4 oFragColor;

float sampleMask(float maskAlpha,
                 sampler2D maskTexture,
                 vec3 maskTexCoord,
                 int maskCtrl){
    if(maskCtrl == 0)
        return maskAlpha;
    float coverage = texture(maskTexture, maskTexCoord . xy). r + maskTexCoord . z;
    if((maskCtrl & 0x1)!= 0)
        coverage = abs(coverage);
    else
        coverage = 1.0 - abs(1.0 - mod(coverage, 2.0));
    return min(maskAlpha, coverage);
}

vec4 sampleColor(sampler2D colorTexture, vec2 colorTexCoord){
    return texture(colorTexture, colorTexCoord);
}

vec2 computeColorTexCoord(vec2 colorTexCoord,
                          int colorFilter,
                          vec4 filterParams0,
                          vec4 filterParams1){
    return colorTexCoord;
}

vec4 filterColor(sampler2D colorTexture,
                 vec2 colorTexCoord,
                 int colorFilter,
                 vec4 filterParams0,
                 vec4 filterParams1){
    colorTexCoord = computeColorTexCoord(colorTexCoord, colorFilter, filterParams0, filterParams1);
    return sampleColor(colorTexture, colorTexCoord);
}

vec4 composite(vec4 color, sampler2D destTexture, vec2 fragCoord){

    return color;
}

void main(){

    int maskCtrl0 =(uCtrl & 0x003)>> 0;
    int maskCtrl1 =(uCtrl & 0x004)>> 2;
    float maskAlpha = 1.0;
    maskAlpha = sampleMask(maskAlpha, uMaskTexture0, vMaskTexCoord0, maskCtrl0);
    maskAlpha = sampleMask(maskAlpha, uMaskTexture1, vMaskTexCoord1, maskCtrl1);


    int color0Filter =(uCtrl & 0x038)>> 0;
    vec4 color = filterColor(uColorTexture0,
                             vColorTexCoord0,
                             color0Filter,
                             uFilterParams0,
                             uFilterParams1);
    if((uCtrl & 0x040)!= 0)
        color *= sampleColor(uColorTexture1, vColorTexCoord1);


    color *= vec4(maskAlpha);


    oFragColor = composite(color, uDestTexture, gl_FragCoord . xy);
}

