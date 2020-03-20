#version {{version}}
// Automatically generated from files in pathfinder/shaders/. Do not edit!

































#extension GL_GOOGLE_include_directive : enable

precision highp float;














































uniform sampler2D uColorTexture0;
uniform sampler2D uColorTexture1;
uniform sampler2D uMaskTexture0;
uniform sampler2D uMaskTexture1;
uniform sampler2D uDestTexture;
uniform sampler2D uGammaLUT;
uniform vec4 uFilterParams0;
uniform vec4 uFilterParams1;
uniform vec4 uFilterParams2;
uniform vec2 uDestTextureSize;
uniform vec2 uColorTexture0Size;
uniform int uCtrl;

in vec3 vMaskTexCoord0;
in vec3 vMaskTexCoord1;
in vec2 vColorTexCoord0;
in vec2 vColorTexCoord1;

out vec4 oFragColor;



vec4 sampleColor(sampler2D colorTexture, vec2 colorTexCoord){
    return texture(colorTexture, colorTexCoord);
}



float filterTextSample1Tap(float offset, sampler2D colorTexture, vec2 colorTexCoord){
    return texture(colorTexture, colorTexCoord + vec2(offset, 0.0)). r;
}


void filterTextSample9Tap(out vec4 outAlphaLeft,
                          out float outAlphaCenter,
                          out vec4 outAlphaRight,
                          sampler2D colorTexture,
                          vec2 colorTexCoord,
                          vec4 kernel,
                          float onePixel){
    bool wide = kernel . x > 0.0;
    outAlphaLeft =
        vec4(wide ? filterTextSample1Tap(- 4.0 * onePixel, colorTexture, colorTexCoord): 0.0,
             filterTextSample1Tap(- 3.0 * onePixel, colorTexture, colorTexCoord),
             filterTextSample1Tap(- 2.0 * onePixel, colorTexture, colorTexCoord),
             filterTextSample1Tap(- 1.0 * onePixel, colorTexture, colorTexCoord));
    outAlphaCenter = filterTextSample1Tap(0.0, colorTexture, colorTexCoord);
    outAlphaRight =
        vec4(filterTextSample1Tap(1.0 * onePixel, colorTexture, colorTexCoord),
             filterTextSample1Tap(2.0 * onePixel, colorTexture, colorTexCoord),
             filterTextSample1Tap(3.0 * onePixel, colorTexture, colorTexCoord),
             wide ? filterTextSample1Tap(4.0 * onePixel, colorTexture, colorTexCoord): 0.0);
}

float filterTextConvolve7Tap(vec4 alpha0, vec3 alpha1, vec4 kernel){
    return dot(alpha0, kernel)+ dot(alpha1, kernel . zyx);
}

float filterTextGammaCorrectChannel(float bgColor, float fgColor, sampler2D gammaLUT){
    return texture(gammaLUT, vec2(fgColor, 1.0 - bgColor)). r;
}


vec3 filterTextGammaCorrect(vec3 bgColor, vec3 fgColor, sampler2D gammaLUT){
    return vec3(filterTextGammaCorrectChannel(bgColor . r, fgColor . r, gammaLUT),
                filterTextGammaCorrectChannel(bgColor . g, fgColor . g, gammaLUT),
                filterTextGammaCorrectChannel(bgColor . b, fgColor . b, gammaLUT));
}






vec4 filterText(vec2 colorTexCoord,
                sampler2D colorTexture,
                sampler2D gammaLUT,
                vec2 colorTextureSize,
                vec4 filterParams0,
                vec4 filterParams1,
                vec4 filterParams2){

    vec4 kernel = filterParams0;
    vec3 bgColor = filterParams1 . rgb;
    vec3 fgColor = filterParams2 . rgb;
    bool gammaCorrectionEnabled = filterParams2 . a != 0.0;


    vec3 alpha;
    if(kernel . w == 0.0){
        alpha = texture(colorTexture, colorTexCoord). rrr;
    } else {
        vec4 alphaLeft, alphaRight;
        float alphaCenter;
        filterTextSample9Tap(alphaLeft,
                             alphaCenter,
                             alphaRight,
                             colorTexture,
                             colorTexCoord,
                             kernel,
                             1.0 / colorTextureSize . x);

        float r = filterTextConvolve7Tap(alphaLeft, vec3(alphaCenter, alphaRight . xy), kernel);
        float g = filterTextConvolve7Tap(vec4(alphaLeft . yzw, alphaCenter), alphaRight . xyz, kernel);
        float b = filterTextConvolve7Tap(vec4(alphaLeft . zw, alphaCenter, alphaRight . x),
                                         alphaRight . yzw,
                                         kernel);

        alpha = vec3(r, g, b);
    }


    if(gammaCorrectionEnabled)
        alpha = filterTextGammaCorrect(bgColor, alpha, gammaLUT);


    return vec4(mix(bgColor, fgColor, alpha), 1.0);
}








vec4 filterBlur(vec2 colorTexCoord,
                sampler2D colorTexture,
                vec2 colorTextureSize,
                vec4 filterParams0,
                vec4 filterParams1){

    vec2 srcOffsetScale = filterParams0 . xy / colorTextureSize;
    int support = int(filterParams0 . z);
    vec3 gaussCoeff = filterParams1 . xyz;


    float gaussSum = gaussCoeff . x;
    vec4 color = texture(colorTexture, colorTexCoord)* gaussCoeff . x;
    gaussCoeff . xy *= gaussCoeff . yz;









    for(int i = 1;i <= support;i += 2){
        float gaussPartialSum = gaussCoeff . x;
        gaussCoeff . xy *= gaussCoeff . yz;
        gaussPartialSum += gaussCoeff . x;

        vec2 srcOffset = srcOffsetScale *(float(i)+ gaussCoeff . x / gaussPartialSum);
        color +=(texture(colorTexture, colorTexCoord - srcOffset)+
                  texture(colorTexture, colorTexCoord + srcOffset))* gaussPartialSum;

        gaussSum += 2.0 * gaussPartialSum;
        gaussCoeff . xy *= gaussCoeff . yz;
    }


    color /= gaussSum;
    color . rgb *= color . a;
    return color;
}

vec4 filterNone(vec2 colorTexCoord, sampler2D colorTexture){
    return sampleColor(colorTexture, colorTexCoord);
}

vec4 filterColor(vec2 colorTexCoord,
                 sampler2D colorTexture,
                 sampler2D gammaLUT,
                 vec2 colorTextureSize,
                 vec4 filterParams0,
                 vec4 filterParams1,
                 vec4 filterParams2,
                 int colorFilter){
    switch(colorFilter){
    case 0x3 :
        return filterBlur(colorTexCoord,
                          colorTexture,
                          colorTextureSize,
                          filterParams0,
                          filterParams1);
    case 0x2 :
        return filterText(colorTexCoord,
                          colorTexture,
                          gammaLUT,
                          colorTextureSize,
                          filterParams0,
                          filterParams1,
                          filterParams2);
    }
    return filterNone(colorTexCoord, colorTexture);
}



vec4 composite(vec4 color, sampler2D destTexture, vec2 fragCoord){

    return color;
}



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



void main(){

    int maskCtrl0 =(uCtrl >> 0)& 0x3;
    int maskCtrl1 =(uCtrl >> 2)& 0x3;
    float maskAlpha = 1.0;
    maskAlpha = sampleMask(maskAlpha, uMaskTexture0, vMaskTexCoord0, maskCtrl0);
    maskAlpha = sampleMask(maskAlpha, uMaskTexture1, vMaskTexCoord1, maskCtrl1);


    int color0Filter =(uCtrl >> 4)& 0x3;
    vec4 color = filterColor(vColorTexCoord0,
                             uColorTexture0,
                             uGammaLUT,
                             uColorTexture0Size,
                             uFilterParams0,
                             uFilterParams1,
                             uFilterParams2,
                             color0Filter);
    if(((uCtrl >> 6)&
                                            0x1)!= 0){
        color *= sampleColor(uColorTexture1, vColorTexCoord1);
    }


    color *= vec4(maskAlpha);


    oFragColor = composite(color, uDestTexture, gl_FragCoord . xy);
}

