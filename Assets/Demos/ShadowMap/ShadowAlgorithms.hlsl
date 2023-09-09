#ifndef SHADOW_ALGORITHMS_INCLUDED
#define SHADOW_ALGORITHMS_INCLUDED

#define DEPTH_BIAS 1e-3

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

// ------------------------------------------------------------------
//  PCF Filtering methods
// ------------------------------------------------------------------

// Hardware Bilinear PCF Comparison, 2x2 PCF (1 tap)
real SampleShadow_Bilinear_PCF(float4 shadowCoord)
{
    return real(SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, shadowCoord.xyz).x);
}

// 3x3 ten PCF sampling (4 taps)
real SampleShadow_PCF_Tent_3x3(float4 shadowCoord)
{
    shadowCoord.z += DEPTH_BIAS;

    real shadow = 0.0;
    real fetchesWeights[4];
    real2 fetchesUV[4];

    SampleShadow_ComputeSamples_Tent_3x3(_MainLightShadowmapSize, shadowCoord.xy, fetchesWeights, fetchesUV);
    UNITY_LOOP
    for (int i = 0; i < 4; i++)
    {
        shadow += fetchesWeights[i] * SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, real3(fetchesUV[i].xy, shadowCoord.z)).x;
    }
    return shadow;
}

// 5x5 tent PCF sampling (9 taps)
real SampleShadow_PCF_Tent_5x5(float4 shadowCoord)
{
    shadowCoord.z += DEPTH_BIAS;

    real shadow = 0.0;
    real fetchesWeights[9];
    real2 fetchesUV[9];

    SampleShadow_ComputeSamples_Tent_5x5(_MainLightShadowmapSize, shadowCoord.xy, fetchesWeights, fetchesUV);

    UNITY_LOOP
    for (int i = 0; i < 9; i++)
    {
        shadow += fetchesWeights[i] * SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, real3(fetchesUV[i].xy, shadowCoord.z)).x;
    }

    return shadow;
}

// 7x7 tent PCF sampling (16 taps)
real SampleShadow_PCF_Tent_7x7(float4 shadowCoord)
{
    shadowCoord.z += DEPTH_BIAS;

    real shadow = 0.0;
    real fetchesWeights[16];
    real2 fetchesUV[16];

    SampleShadow_ComputeSamples_Tent_7x7(_MainLightShadowmapSize, shadowCoord.xy, fetchesWeights, fetchesUV);

    UNITY_LOOP
    for (int i = 0; i < 16; i++)
    {
        shadow += fetchesWeights[i] * SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, real3(fetchesUV[i].xy, shadowCoord.z)).x;
    }

    return shadow;
}

#endif
