Shader "Hidden/URP Graphics/Post-processing/AddSpecularOnly"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off Cull Off

        Stencil
        {
            Ref 16
            Comp Equal
        }

        Pass
        {
            Name "Add Specular Only Pass"

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            TEXTURE2D_X(_SpecularTex);
            TEXTURE2D_X(_ColorTex);

            void frag(Varyings input, out half4 outColor : SV_Target)
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Fetch color of current pixel:
                half4 colorM = SAMPLE_TEXTURE2D_X(_ColorTex, sampler_LinearRepeat, input.texcoord);

                if (colorM.a == 0.0)
                    discard;

                colorM.rgb += SAMPLE_TEXTURE2D_X(_SpecularTex, sampler_LinearRepeat, input.texcoord).rgb;

                outColor = colorM;
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
