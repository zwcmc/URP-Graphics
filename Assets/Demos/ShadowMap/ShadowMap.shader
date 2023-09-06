Shader "URP Graphics/ShadowMap/ShadowMap"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (0.8, 0.8, 0.8, 1.0)
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

        Pass
        {
            Name "Shadow Map Blinn Phong Lit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            ZWrite On

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _Uks;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.normalWS = normalInput.normalWS;

                output.positionWS = vertexInput.positionWS;

                output.positionCS = vertexInput.positionCS;
                return output;
            }

            void frag(Varyings input, out half4 outColor : SV_Target)
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;

                half3 ambient = 0.05 * albedo;

                Light mainLight = GetMainLight();

                half3 lightDirectionWS = normalize(mainLight.direction);
                half3 normalWS = NormalizeNormalPerPixel(input.normalWS);

                half diff = saturate(dot(normalWS, lightDirectionWS));

                half3 lightAttenCoff = mainLight.distanceAttenuation;

                half3 diffuse = diff * lightAttenCoff * albedo;

                half3 viewDirectionWS = normalize(GetWorldSpaceViewDir(input.positionWS));
                half3 halfDir = normalize(lightDirectionWS + viewDirectionWS);
                half spec = pow(saturate(dot(normalWS, halfDir)), 32.0);
                half3 specular = _Uks.rgb * lightAttenCoff * spec;

                // visibility
                half cascadeIndex = ComputeCascadeIndex(input.positionWS);
                float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(input.positionWS, 1.0));
                shadowCoord.xyz /= shadowCoord.w;

                float depth = SAMPLE_TEXTURE2D_X(_MainLightShadowmapTexture, sampler_PointClamp, shadowCoord.xy).r;
                half visibility = depth > shadowCoord.z - 1e-3 ? 0.0 : 1.0;
                // real(SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare, shadowCoord.xyz));// depth > shadowCoord.z - 1e-3 ? 0.0 : 1.0;

                outColor = half4((ambient + diffuse + specular) * visibility, 1.0);
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
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            // Shadow Casting Light geometric parameters. These variables are used when applying the shadow Normal Bias and are set by UnityEngine.Rendering.Universal.ShadowUtils.SetupShadowCasterConstantBuffer in com.unity.render-pipelines.universal/Runtime/ShadowUtils.cs
            // For Directional lights, _LightDirection is used when applying shadow Normal Bias.
            // For Spot lights and Point lights, _LightPosition is used to compute the actual light direction because it is different at each shadow caster geometry vertex.
            float3 _LightDirection;
            float3 _LightPosition;

            float4 _ShadowBias; // x: depth bias, y: normal bias

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _Uks;
            CBUFFER_END

            float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
            {
                float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
                float scale = invNdotL * _ShadowBias.y;

                // normal bias is negative since we want to apply an inset normal offset
                positionWS = lightDirection * _ShadowBias.xxx + positionWS;
                positionWS = normalWS * scale.xxx + positionWS;
                return positionWS;
            }

            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif

                return positionCS;
            }

            float4 vert(Attributes input) : SV_POSITION
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                return GetShadowPositionHClip(input);
            }

            void frag(Varyings input, out half4 outColor : SV_TARGET)
            {
                outColor =  0;
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
