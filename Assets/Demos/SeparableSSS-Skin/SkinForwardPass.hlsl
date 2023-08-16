#ifndef SKIN_FORWARD_PASS_INCLUDED
#define SKIN_FORWARD_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 texcoord : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    half4 tangentWS : TEXCOORD3;  // xyz: tangent, w: sign
    half  fogFactor : TEXCOORD4;
    float4 shadowCoord : TEXCOORD5;
    half3 vertexSH : TEXCOORD6;
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

struct SkinInputData
{
    float3  positionWS;
    float4  positionCS;
    float3  normalWS;
    half3   viewDirectionWS;
    float4  shadowCoord;
    half    fogCoord;
    half3   bakedGI;
    half3x3 tangentToWorld;
};

struct SkinBRDFData
{
    half3 albedo;
    half3 diffuse;
    half3 specular;
    half reflectivity;
    half perceptualRoughness;
    half roughness;
    half roughness2;
    half grazingTerm;

    // We save some light invariant BRDF terms so we don't have to recompute
    // them in the light loop. Take a look at DirectBRDF function for detailed explaination.
    half normalizationTerm;     // roughness * 4.0 + 2.0
    half roughness2MinusOne;    // roughness^2 - 1.0
};

void InitializeInputData(Varyings input, half3 normalTS, out SkinInputData inputData)
{
    inputData = (SkinInputData)0;

    inputData.positionWS = input.positionWS;

    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(_NORMALMAP)
    float sgn = input.tangentWS.w;      // should be either +1 or -1
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);

    #if defined(_NORMALMAP)
        inputData.tangentToWorld = tangentToWorld;
    #endif
    inputData.normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
#else
    inputData.normalWS = input.normalWS;
#endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactor);
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
}

inline void InitializeBRDFData(inout SkinSurfaceData surfaceData, out SkinBRDFData outBRDFData)
{
    outBRDFData = (SkinBRDFData)0;

    half3 albedo = surfaceData.albedo;
    half metallic = surfaceData.metallic;
    half smoothness = surfaceData.smoothness;

    half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
    half reflectivity = half(1.0) - oneMinusReflectivity;
    half3 brdfDiffuse = albedo * oneMinusReflectivity;
    half3 brdfSpecular = lerp(kDieletricSpec.rgb, albedo, metallic);

    outBRDFData.albedo = albedo;
    outBRDFData.diffuse = brdfDiffuse;
    outBRDFData.specular = brdfSpecular;
    outBRDFData.reflectivity = reflectivity;

    outBRDFData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    outBRDFData.roughness           = max(PerceptualRoughnessToRoughness(outBRDFData.perceptualRoughness), HALF_MIN_SQRT);
    outBRDFData.roughness2          = max(outBRDFData.roughness * outBRDFData.roughness, HALF_MIN);
    outBRDFData.grazingTerm         = saturate(smoothness + reflectivity);
    outBRDFData.normalizationTerm   = outBRDFData.roughness * half(4.0) + half(2.0);
    outBRDFData.roughness2MinusOne  = outBRDFData.roughness2 - half(1.0);
}

half3 SSSSTransmittance(half translucency, half sssWidth, float3 positionWS, half3 normalWS, half3 lightDirectionWS)
{
    // Calculate the scale of the effect.
    float scale = 8.25 * (1.0 - translucency) / sssWidth;

    // First we shrink the position inwards the surface to avoid artifacts: (Note that this can be done once for all the lights)
    float4 shrinkedPos = float4(positionWS - 0.005 * normalWS, 1.0);

    // Now we calculate the thickness from the light point of view:
#ifdef _MAIN_LIGHT_SHADOWS_CASCADE
    half cascadeIndex = ComputeCascadeIndex(positionWS);
#else
    half cascadeIndex = half(0.0);
#endif
    float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], shrinkedPos);
    shadowCoord.xyz /= shadowCoord.w;

    float d1 = SAMPLE_TEXTURE2D_X(_MainLightShadowmapTexture, sampler_LinearClamp, shadowCoord.xy).r;
    float d2 = shadowCoord.z + 0.001;
    float d = scale * abs(d1 - d2);

    // Armed with the thickness, we can now calculate the color by means of the precalculated transmittance profile.(It can be precomputed into a texture, for maximum performance):
    float dd = -d * d;
    half3 profile = half3(0.233, 0.455, 0.649) * exp(dd / 0.0064) +
                     half3(0.1, 0.336, 0.344) * exp(dd / 0.0484) +
                     half3(0.118, 0.198, 0.0)   * exp(dd / 0.187)  +
                     half3(0.113, 0.007, 0.007) * exp(dd / 0.567)  +
                     half3(0.358, 0.004, 0.0)   * exp(dd / 1.99)   +
                     half3(0.078, 0.0,   0.0)   * exp(dd / 7.41);

    // Using the profile, we finally approximate the transmitted lighting from the back of the object:
    return profile * saturate(0.3 + dot(lightDirectionWS, -normalWS));
}

half4 SeparableSSSSkinPBR(SkinInputData inputData, SkinSurfaceData surfaceData)
{
    SkinBRDFData brdfData;
    InitializeBRDFData(surfaceData, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, half4(0.0, 0.0, 0.0, 0.0));

    half3 viewDirectionWS = inputData.viewDirectionWS;
    half3 normalWS = inputData.normalWS;
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    // Environment BRDF
    half3 indirectDiffuse = inputData.bakedGI;
    half3 indirectSpecular;
    half mip = PerceptualRoughnessToMipmapLevel(brdfData.perceptualRoughness);
    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));
    indirectSpecular = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
    half3 envDiffuse = indirectDiffuse * brdfData.diffuse;
    float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    half3 envSpecular = indirectSpecular * half3(surfaceReduction * lerp(brdfData.specular, brdfData.grazingTerm, fresnelTerm));
    half3 giColor = envDiffuse + envSpecular;

    half3 lightColor = mainLight.color;
    half3 lightDirectionWS = mainLight.direction;
    half lightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;

    half NdotL = saturate(dot(normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);

    half3 brdf = brdfData.diffuse;
    float3 lightDirectionWSFloat3 = float3(lightDirectionWS);
    float3 halfDir = SafeNormalize(lightDirectionWSFloat3 + float3(viewDirectionWS));

    float NoH = saturate(dot(float3(normalWS), halfDir));
    half LoH = half(saturate(dot(lightDirectionWSFloat3, halfDir)));
    float d = NoH * NoH * brdfData.roughness2MinusOne + 1.00001f;
    half LoH2 = LoH * LoH;
    half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) * brdfData.normalizationTerm);

#if REAL_IS_HALF
    specularTerm = specularTerm - HALF_MIN;
    // Update: Conservative bump from 100.0 to 1000.0 to better match the full float specular look.
    // Roughly 65504.0 / 32*2 == 1023.5,
    // or HALF_MAX / ((mobile) MAX_VISIBLE_LIGHTS * 2),
    // to reserve half of the per light range for specular and half for diffuse + indirect + emissive.
    specularTerm = clamp(specularTerm, 0.0, 1000.0); // Prevent FP16 overflow on mobiles
#endif

    brdf += brdfData.specular * specularTerm;

    half3 mainLightColor = brdf * radiance;

    return half4(giColor + mainLightColor, 1.0);
}

half4 SeparableSSSSkinPBRDiffuse(SkinInputData inputData, SkinSurfaceData surfaceData)
{
    SkinBRDFData brdfData;
    InitializeBRDFData(surfaceData, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, half4(0.0, 0.0, 0.0, 0.0));

    half3 normalWS = inputData.normalWS;

    // Environment Diffuse
    half3 indirectDiffuse = inputData.bakedGI;
    half3 envDiffuse = indirectDiffuse * brdfData.diffuse;
    half3 giColor = envDiffuse;

    // Direct Diffuse
    half3 lightColor = mainLight.color;
    half3 lightDirectionWS = mainLight.direction;
    half lightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    half NdotL = saturate(dot(normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);
    half3 brdf = brdfData.diffuse;
    half3 mainLightColor = brdf * radiance;

    // Transmittance
    // half sssWidth = 0.025 * _SSSWidth;
    // half translucency = _Translucency;
    // float3 positionWS = inputData.positionWS;
    // half3 trans = SSSSTransmittance(translucency, sssWidth, positionWS, normalWS, lightDirectionWS);
    // half3 transmittance = lightColor * lightAttenuation * trans;

    return half4(giColor + mainLightColor, 1.0);
}

half4 SeparableSSSSkinPBRSpecular(SkinInputData inputData, SkinSurfaceData surfaceData)
{
    SkinBRDFData brdfData;
    InitializeBRDFData(surfaceData, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, half4(0.0, 0.0, 0.0, 0.0));

    half3 viewDirectionWS = inputData.viewDirectionWS;
    half3 normalWS = inputData.normalWS;
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    // Environment Specular
    half3 indirectSpecular;
    half mip = PerceptualRoughnessToMipmapLevel(brdfData.perceptualRoughness);
    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));
    indirectSpecular = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
    float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    half3 envSpecular = indirectSpecular * half3(surfaceReduction * lerp(brdfData.specular, brdfData.grazingTerm, fresnelTerm));
    half3 giColor = envSpecular;


    // Direct Specular
    half3 lightColor = mainLight.color;
    half3 lightDirectionWS = mainLight.direction;
    half lightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;

    half NdotL = saturate(dot(normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);

    float3 lightDirectionWSFloat3 = float3(lightDirectionWS);
    float3 halfDir = SafeNormalize(lightDirectionWSFloat3 + float3(viewDirectionWS));

    float NoH = saturate(dot(float3(normalWS), halfDir));
    half LoH = half(saturate(dot(lightDirectionWSFloat3, halfDir)));
    float d = NoH * NoH * brdfData.roughness2MinusOne + 1.00001f;
    half LoH2 = LoH * LoH;
    half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) * brdfData.normalizationTerm);

#if REAL_IS_HALF
    specularTerm = specularTerm - HALF_MIN;
    // Update: Conservative bump from 100.0 to 1000.0 to better match the full float specular look.
    // Roughly 65504.0 / 32*2 == 1023.5,
    // or HALF_MAX / ((mobile) MAX_VISIBLE_LIGHTS * 2),
    // to reserve half of the per light range for specular and half for diffuse + indirect + emissive.
    specularTerm = clamp(specularTerm, 0.0, 1000.0); // Prevent FP16 overflow on mobiles
#endif

    half3 mainLightColor = brdfData.specular * specularTerm * radiance;

    return half4(giColor + mainLightColor, 1.0);
}

Varyings SeparableSSSSkinVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

    // normalWS and tangentWS already normalize.
    // this is required to avoid skewing the direction during interpolation
    // also required for per-vertex lighting and SH evaluation
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

    // already normalized from normal transform to WS.
    output.normalWS = normalInput.normalWS;

    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = half4(normalInput.tangentWS.xyz, sign);

    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

    output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

    output.positionWS = vertexInput.positionWS;

    output.shadowCoord = GetShadowCoord(vertexInput);

    output.positionCS = vertexInput.positionCS;

    return output;
}

void DiffusePassFragment(Varyings input, out half4 outColor : SV_Target)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SkinSurfaceData surfaceData;
    InitializeSurfaceData(input.uv, surfaceData);

    SkinInputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);

    half4 color = SeparableSSSSkinPBRDiffuse(inputData, surfaceData);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);

    outColor = color;
}

void SpecularPassFragment(Varyings input, out half4 outColor : SV_Target)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SkinSurfaceData surfaceData;
    InitializeSurfaceData(input.uv, surfaceData);

    SkinInputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);

    half4 color = SeparableSSSSkinPBRSpecular(inputData, surfaceData);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);

    outColor = color;
}

#endif
