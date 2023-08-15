#ifndef SKIN_INPUT_INCLUDED
#define SKIN_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
half4 _BaseColor;
half _Smoothness;
half _Metallic;
half _BumpScale;
CBUFFER_END

TEXTURE2D(_BaseMap);                SAMPLER(sampler_BaseMap);
TEXTURE2D(_MetallicGlossMap);       SAMPLER(sampler_MetallicGlossMap);
TEXTURE2D(_BumpMap);                SAMPLER(sampler_BumpMap);

struct SkinSurfaceData
{
    half3 albedo;
    half metallic;
    half smoothness;
    half3 normalTS;
};

half4 SampleMetallicSpecGloss(float2 uv)
{
    half4 specGloss;

#ifdef _METALLICSPECGLOSSMAP
    specGloss = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uv);
    specGloss.a *= _Smoothness;
#else
    specGloss.rgb = _Metallic.rrr;
    specGloss.a = _Smoothness;
#endif

    return specGloss;
}

half3 SampleNormal(float2 uv, TEXTURE2D_PARAM(bumpMap, sampler_bumpMap), half scale = half(1.0))
{
#ifdef _NORMALMAP
    half4 n = SAMPLE_TEXTURE2D(bumpMap, sampler_bumpMap, uv);
    #if BUMP_SCALE_NOT_SUPPORTED
        return UnpackNormal(n);
    #else
        return UnpackNormalScale(n, scale);
    #endif
#else
    return half3(0.0h, 0.0h, 1.0h);
#endif
}

inline void InitializeSurfaceData(float2 uv, out SkinSurfaceData outSurfaceData)
{
    half4 albedoAlpha = half4(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv));
    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;

    half4 specGloss = SampleMetallicSpecGloss(uv);
    outSurfaceData.metallic = specGloss.r;
    outSurfaceData.smoothness = specGloss.a;

    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
}

#endif
