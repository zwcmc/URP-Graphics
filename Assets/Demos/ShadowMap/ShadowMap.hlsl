#ifndef SHADOW_MAP_INCLUDED
#define SHADOW_MAP_INCLUDED

// Standard Shadow Map
real UseShadowMap(float4 shadowCoord)
{
    float shadowMapDepth = SAMPLE_TEXTURE2D_X_LOD(_MainLightShadowmapTexture, sampler_PointClamp, shadowCoord.xy, 0).r;
#if UNITY_REVERSED_Z
    return shadowCoord.z > shadowMapDepth ? 1.0 : 0.0;
#else
    return shadowCoord.z < shadowMapDepth ? 1.0 : 0.0;
#endif
}

// Hardware Bilinear PCF Comparison, 2x2 PCF (1 tap)
real SampleShadow_Bilinear_PCF(float4 shadowCoord)
{
    return real(SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, shadowCoord.xyz));
}

#endif
