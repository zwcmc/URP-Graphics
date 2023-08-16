Shader "Hidden/URP Graphics/Post-processing/SeparableSSS"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off Cull Off

        Stencil
        {
            Ref 16
            Comp Equal
        }

        Pass
        {
            Name "Separable Subsurface Scattering Blur Pass"

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma multi_compile_local_fragment _ _SSSS_FOLLOW_SURFACE

            #pragma vertex Vert
            #pragma fragment FragSeparableSSS

            TEXTURE2D_X(_ColorTex);                      SAMPLER(sampler_ColorTex);
            TEXTURE2D_X(_SpecularTex);                     SAMPLER(sampler_SpecularTex);
            TEXTURE2D_X_FLOAT(_CameraDepthTexture);      SAMPLER(sampler_CameraDepthTexture);

            #define SSSS_N_SAMPLES 17
            #define SSSS_FOVY 20.0

            float _SssWidth;
            float4 _Kernel[SSSS_N_SAMPLES];
            float4 _BlurDir;

            float _FinalAddSpecular;

            void FragSeparableSSS(Varyings input, out half4 outColor : SV_Target)
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Fetch color of current pixel:
                half4 colorM = SAMPLE_TEXTURE2D_X(_ColorTex, sampler_ColorTex, input.texcoord);

                if (colorM.a == 0.0)
                    discard;

                // Fetch linear depth of current pixel:
                float depthM = LinearEyeDepth(SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord).r, _ZBufferParams);

                // Calculate the sssWidth scale (1.0 for a unit plane sitting on the projection window):
                float distanceToProjectionWindow = 1.0 / tan(0.5 * radians(SSSS_FOVY));
                float scale = distanceToProjectionWindow / max(depthM, 0.00001);

                // Calculate the final step to fetch the surrounding pixels:
                float2 finalStep = _SssWidth * scale * _BlurDir.xy;
                finalStep *= colorM.a; // Modulate it using the alpha channel.
                finalStep *= 1.0 / 3.0; // Divide by 3 as the kernels range from -3 to 3.

                // Accumulate the center sample:
                half4 colorBlurred = colorM;
                colorBlurred.rgb *= _Kernel[0].rgb;

                // Accumulate the other samples:
                UNITY_UNROLL
                for (int i = 1; i < SSSS_N_SAMPLES; i++) {
                    // Fetch color and depth for current sample:
                    float2 offset = input.texcoord + _Kernel[i].a * finalStep;
                    float4 color = SAMPLE_TEXTURE2D_X(_ColorTex, sampler_ColorTex, offset);

                    #ifdef _SSSS_FOLLOW_SURFACE
                        // If the difference in depth is huge, we lerp color back to "colorM":
                        float depth = LinearEyeDepth(SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, offset).r, _ZBufferParams);
                        float s = saturate(300.0f * distanceToProjectionWindow * _SssWidth * abs(depthM - depth));
                        color.rgb = lerp(color.rgb, colorM.rgb, s);
                    #endif

                    // Accumulate:
                    colorBlurred.rgb += _Kernel[i].rgb * color.rgb;
                }

                // Add specular
                colorBlurred.rgb += _FinalAddSpecular > 0.5 ? SAMPLE_TEXTURE2D_X(_SpecularTex, sampler_SpecularTex, input.texcoord).rgb : 0.0;

                outColor = colorBlurred;
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
