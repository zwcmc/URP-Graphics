Shader "URP Graphics/SeparableSSS/Skin"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)

        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        [IntRange] _StencilReference("Stencil Reference Value", Range(0, 255)) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComparison("Stencil Comparison", Float) = 8
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilPass("Stencil Pass", Float) = 0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 300

        Pass
        {
            Name "SeparableSSS Skin Diffuse"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            ZWrite On
            ZTest LEqual
            Cull Back

            Stencil
            {
                Ref [_StencilReference]
                Comp [_StencilComparison]
                Pass [_StencilPass]
            }

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex SeparableSSSSkinVertex
            #pragma fragment DiffusePassFragment

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "SkinInput.hlsl"
            #include "SkinForwardPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "SeparableSSS Skin Specular"
            Tags
            {
                "LightMode" = "SeparableSSSSkinSpecularPass"
            }

            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex SeparableSSSSkinVertex
            #pragma fragment SpecularPassFragment

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "SkinInput.hlsl"
            #include "SkinForwardPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex SeparableSSSSkinShadowPassVertex
            #pragma fragment SeparableSSSSkinShadowPassFragment

            #include "SkinInput.hlsl"
            #include "SkinShadowCasterPass.hlsl"

            ENDHLSL
        }
    }

    CustomEditor "URPGraphics.ShaderGUI.SkinShader"
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
