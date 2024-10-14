Shader "URP Graphics/Disney_BRDF"
{
    Properties
    {
        [MainColor] _BaseColor("Color", Color) = (1, 1, 1, 1)

        _Metallic("Metallic", Range(0,1)) = 0.5
        _Roughness("Roughness", Range(0,1)) = 0.233

        _Anisotropic("Anisotropic", Range(0,1)) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend One Zero
        ZWrite On
        Cull Back

        Pass
        {
            Name "Disney_BRDF"

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half _Metallic;
                half _Roughness;
                half _Anisotropic;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS    : POSITION;
                float3 normalOS      : NORMAL;
                float4 tangentOS     : TANGENT;
            };

            struct Varyings
            {
                float3 positionWS    : TEXCOORD1;
                half4 normalWS       : TEXCOORD2;
                half4 tangentWS      : TEXCOORD3;
                half4 bitangentWS    : TEXCOORD4;
                float4 positionCS    : SV_POSITION;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionWS = vertexInput.positionWS;

                half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
                output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
                output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);

                output.positionCS = vertexInput.positionCS;

                return output;
            }

            float Sqr(float x)
            {
                return x * x;
            }

            float SchlickFresnel(float u)
            {
                // pow((1.0 - u), 5.0)
                float m = clamp(1.0 - u, 0.0, 1.0);
                float m2 = m * m;
                return m2 * m2 * m; // pow(m, 5.0)
            }

            float DisneyDiffuseInvPi(float NdotL, float NdotV, float LdotH, float perceptualRoughness)
            {
                float Fd90 = 0.5 + 2.0 * perceptualRoughness * LdotH * LdotH;

                float FL = SchlickFresnel(NdotL);
                float FV = SchlickFresnel(NdotV);

                return INV_PI * lerp(1.0, Fd90, FL) * lerp(1.0, Fd90, FV); // (1.0 / π ) * (1.0 + (Fd90 - 1.0) * FL)(1.0 + (Fd90 - 1.0) * FV)
            }

            // Anisotropy GGX(Trowbridge-Reitz) Distribution
            float GTR2_aniso(float NdotH, float HdotX, float HdotY, float ax, float ay)
            {
                return 1.0 / (PI * ax * ay * Sqr(Sqr(HdotX / ax) + Sqr(HdotY / ay) + NdotH * NdotH));
            }

            // Anisotropy Smith-G-GGX
            float SmithG_GGX_aniso(float NdotV, float VdotX, float VdotY, float ax, float ay)
            {
                return 1.0 / (NdotV + sqrt(Sqr(VdotX * ax) + Sqr(VdotY * ay) + Sqr(NdotV)));
            }

            half4 Frag(Varyings input) : SV_Target
            {
                Light light = GetMainLight();

                half metallic = _Metallic;
                half perceptualRoughness = _Roughness;

                half3 N = normalize(input.normalWS.xyz);
                half3 X = normalize(input.tangentWS.xyz);
                half3 Y = normalize(input.bitangentWS.xyz);
                half3 V = normalize(half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w));
                half3 L = normalize(light.direction);
                half3 H = normalize(L + V);

                half NdotL = max(dot(N, L), 0.0);
                half NdotV = max(dot(N, V), 0.0);
                half NdotH = max(dot(N, H), 0.0);
                half LdotH = max(dot(L, H), 0.0);

                half3 baseColor = _BaseColor.rgb;
                half3 radiance = light.color;

                half3 Lo;

                half3 diffuseColor = baseColor * (1.0 - metallic);
                half reflectance = 0.04;
                half3 F0 = lerp(half3(reflectance.xxx), baseColor, metallic);

                half3 Fd = diffuseColor * DisneyDiffuseInvPi(NdotL, NdotV, LdotH, perceptualRoughness);

                half a = perceptualRoughness * perceptualRoughness;

                half aspect = sqrt(1.0 - _Anisotropic * 0.9);
                float ax = max(0.001, a / aspect);
                float ay = max(0.001, a * aspect);

                // Specular D
                float Ds = GTR2_aniso(NdotH, dot(H, X), dot(H, Y), ax, ay);

                // Specular F
                float FH = SchlickFresnel(LdotH);
                half3 Fs = lerp(F0, half3(1,1,1), FH);

                // Specular G
                float Gs;
                Gs  = SmithG_GGX_aniso(NdotL, dot(L, X), dot(L, Y), ax, ay);
                Gs *= SmithG_GGX_aniso(NdotV, dot(V, X), dot(V, Y), ax, ay);

                // Fr
                half3 Fr = Ds * Fs * Gs;

                // BRDF
                half3 BRDF = Fd + Fr;

                // Lo = Li * BRDF * cosine
                Lo = radiance * BRDF * NdotL;

                return half4(Lo, 1.0);
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
