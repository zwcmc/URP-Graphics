Shader "URP Graphics/ShadowMap/ShadowMap"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
        _Uks("Specular", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }

        HLSLINCLUDE
        #pragma target 4.5

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        half4 _BaseColor;
        half4 _Uks;
        CBUFFER_END

        TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
        ENDHLSL

        Pass
        {
            Name "Shadow Map Blinn Phong Lit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            ZWrite On

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "ShadowAlgorithms.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.normalWS = normalInput.normalWS;

                output.positionWS = vertexInput.positionWS;

                output.positionCS = vertexInput.positionCS;
                return output;
            }

            void Frag(Varyings input, out half4 outColor : SV_Target)
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;

                half3 giColor = 0.05 * albedo;

                Light mainLight = GetMainLight();

                half3 lightDirectionWS = normalize(mainLight.direction);
                half3 normalWS = NormalizeNormalPerPixel(input.normalWS);

                half3 attenuatedLightColor = mainLight.color * mainLight.distanceAttenuation;
                half3 lightDiffuseColor = LightingLambert(attenuatedLightColor, lightDirectionWS, normalWS);

                half3 viewDirectionWS = normalize(GetWorldSpaceViewDir(input.positionWS));
                half3 lightSpecularColor = LightingSpecular(attenuatedLightColor, lightDirectionWS, normalWS, viewDirectionWS, half4(_Uks.rgb, 1), 32.0);

                // shadow coeff
                half cascadeIndex = ComputeCascadeIndex(input.positionWS);
                float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(input.positionWS, 1.0));

                half shadowCoeff = half(SampleShadow_PCF_Tent_5x5(shadowCoord));

                outColor = half4(giColor + (lightDiffuseColor * albedo + lightSpecularColor) * shadowCoeff, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS   : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float4 positionCS = TransformObjectToHClip(input.positionOS.xyz);
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif

                return positionCS;
            }

            void frag(out half4 outColor : SV_TARGET)
            {
                outColor =  0;
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
