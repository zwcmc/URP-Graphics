using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class SeparableSSSRenderPassFeature : ScriptableRendererFeature
{
    class SeparableSSSRenderPass : ScriptableRenderPass
    {
        ProfilingSampler m_ProfilingSampler = new ProfilingSampler("Separable Subsurface Scattering Pass");

        SeparableSSS m_SeparableSSS;
        Material m_Material;
        RTHandle m_CameraColorTarget;
        RTHandle m_CameraDepthTarget;
        RTHandle m_TempTarget;
        private RTHandle m_SpecularTarget;

        static readonly int _ColorTexId = Shader.PropertyToID("_ColorTex");
        static readonly int _SpecularTexId = Shader.PropertyToID("_SpecularTex");
        static readonly int _KernelId = Shader.PropertyToID("_Kernel");
        static readonly int _SssWidthId = Shader.PropertyToID("_SssWidth");
        static readonly int _BlurDirId = Shader.PropertyToID("_BlurDir");
        static readonly int _AddSpecularId = Shader.PropertyToID("_AddSpecular");
        const int SSSS_N_SAMPLES = 17;
        Vector4[] m_Kernel = new Vector4[SSSS_N_SAMPLES];

        public SeparableSSSRenderPass(Material material)
        {
            m_Material = material;
        }

        public void Setup(RTHandle colorHandle, RTHandle depthHandle)
        {
            m_CameraColorTarget = colorHandle;
            m_CameraDepthTarget = depthHandle;
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var stack = VolumeManager.instance.stack;
            m_SeparableSSS = stack.GetComponent<SeparableSSS>();

            if (m_SeparableSSS == null) return;

            var cameraData = renderingData.cameraData;
            if (cameraData.camera.cameraType != CameraType.Game) return;

            if (m_Material == null) return;

            CommandBuffer cmd = CommandBufferPool.Get(name: "Separable Subsurface Scattering");

            // Render Separable SSS Specular
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                RenderingUtils.ReAllocateIfNeeded(ref m_SpecularTarget, m_CameraColorTarget.rt.descriptor,
                    FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SpecularTarget");

                CoreUtils.SetRenderTarget(cmd, m_SpecularTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    m_CameraDepthTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);

                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                List<ShaderTagId> shaderTagIdList = new List<ShaderTagId>();
                shaderTagIdList.Add(new ShaderTagId("SeparableSSSSkinSpecularPass"));
                var sortFlags = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawSettings = RenderingUtils.CreateDrawingSettings(shaderTagIdList, ref renderingData, sortFlags);
                FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
                RenderStateBlock renderStateBlock = new RenderStateBlock(RenderStateMask.Depth);
                renderStateBlock.depthState = new DepthState(true, CompareFunction.LessEqual);
                context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filteringSettings, ref renderStateBlock);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();




                // Render Separable SSS
                RenderingUtils.ReAllocateIfNeeded(ref m_TempTarget, m_CameraColorTarget.rt.descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempTarget");

                float sssWidth = 0.025f * m_SeparableSSS.sSSWidth.value;
                bool followSurface = m_SeparableSSS.followSurface.value;
                Vector3 strength = new Vector3(m_SeparableSSS.strength.value.r, m_SeparableSSS.strength.value.g, m_SeparableSSS.strength.value.b);
                Vector3 falloff = new Vector3(m_SeparableSSS.falloff.value.r, m_SeparableSSS.falloff.value.g, m_SeparableSSS.falloff.value.b);

                CalculateKernel(strength, falloff);
                cmd.SetGlobalFloat(_SssWidthId, sssWidth);

                if (followSurface)
                    m_Material.EnableKeyword("_SSSS_FOLLOW_SURFACE");
                else
                    m_Material.DisableKeyword("_SSSS_FOLLOW_SURFACE");

                cmd.SetGlobalTexture(_ColorTexId, m_CameraColorTarget.nameID);
                cmd.SetGlobalVector(_BlurDirId, new Vector4(1.0f, 0.0f, 0.0f, 0.0f));
                cmd.SetGlobalFloat(_AddSpecularId, 0.0f);
                CoreUtils.SetRenderTarget(cmd,
                    m_TempTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    m_CameraDepthTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    ClearFlag.None, Color.clear); // implicit depth=1.0f stencil=0x0
                Blitter.BlitTexture(cmd, m_CameraColorTarget, Vector2.one, m_Material, 0);

                cmd.SetGlobalTexture(_ColorTexId, m_TempTarget.nameID);
                cmd.SetGlobalVector(_BlurDirId, new Vector4(0.0f, 1.0f, 0.0f, 0.0f));
                cmd.SetGlobalTexture(_SpecularTexId, m_SpecularTarget.nameID);
                cmd.SetGlobalFloat(_AddSpecularId, 1.0f);
                CoreUtils.SetRenderTarget(cmd,
                    m_CameraColorTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    m_CameraDepthTarget, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    ClearFlag.None, Color.clear); // implicit depth=1.0f stencil=0x0
                Blitter.BlitTexture(cmd, m_TempTarget, Vector2.one, m_Material, 0);
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }

        #region Separable Subsurface Scattering Funcions

        Vector3 Gaussian(float variance, float r, Vector3 falloff)
        {
            // We use a falloff to modulate the shape of the profile. Big falloffs
            // spreads the shape making it wider, while small falloffs make it narrower.
            Vector3 g = Vector3.zero;
            for (int i = 0; i < 3; i++)
            {
                float rr = r / (0.001f + falloff[i]);
                g[i] = (float)(Math.Exp((-(rr * rr)) / (2.0f * variance)) / (2.0f * 3.14f * variance));
            }
            return g;
        }

        Vector3 Profile(float r, Vector3 falloff)
        {
            // We used the red channel of the original skin profile defined in
            // [d'Eon07] for all three channels. We noticed it can be used for green
            // and blue channels (scaled using the falloff parameter) without
            // introducing noticeable differences and allowing for total control over
            // the profile. For example, it allows to create blue SSS gradients, which
            // could be useful in case of rendering blue creatures.
            return  //  0.233f * gaussian(0.0064f, r) + /* We consider this one to be directly bounced light, accounted by the strength parameter (see @STRENGTH) */
                        0.100f * Gaussian(0.0484f, r, falloff) +
                        0.118f * Gaussian( 0.187f, r, falloff) +
                        0.113f * Gaussian( 0.567f, r, falloff) +
                        0.358f * Gaussian(  1.99f, r, falloff) +
                        0.078f * Gaussian(  7.41f, r, falloff);
        }

        void CalculateKernel(Vector3 strength, Vector3 falloff)
        {
            const int nSamples = SSSS_N_SAMPLES;
            const float RANGE = nSamples > 20 ? 3.0f : 2.0f;
            const float EXPONENT = 2.0f;

            // Calculate the offsets:
            float step = 2.0f * RANGE / (nSamples - 1);
            for (int i = 0; i < nSamples; i++)
            {
                float o = -RANGE + i * step;
                float sign = o < 0.0f ? -1.0f : 1.0f;
                m_Kernel[i].w = (float)(RANGE * sign * Math.Abs(Math.Pow(o, EXPONENT)) / Math.Pow(RANGE, EXPONENT));
            }

            // Calculate the weights:
            for (int i = 0; i < nSamples; i++)
            {
                float w0 = i > 0 ? Math.Abs(m_Kernel[i].w - m_Kernel[i - 1].w) : 0.0f;
                float w1 = i < nSamples - 1 ? Math.Abs(m_Kernel[i].w - m_Kernel[i + 1].w) : 0.0f;
                float area = (w0 + w1) / 2.0f;
                Vector3 t = area * Profile(m_Kernel[i].w, falloff);
                m_Kernel[i].x = t.x;
                m_Kernel[i].y = t.y;
                m_Kernel[i].z = t.z;
            }

            // We want the offset 0.0 to come first:
            Vector4 tMid = m_Kernel[nSamples / 2];
            for (int i = nSamples / 2; i > 0; i--)
                m_Kernel[i] = m_Kernel[i - 1];
            m_Kernel[0] = tMid;

            // Calculate the sum of the weights, we will need to normalize them below:
            Vector3 sum = Vector3.zero;
            for (int i = 0; i < nSamples; i++)
            {
                sum += new Vector3(m_Kernel[i].x, m_Kernel[i].y, m_Kernel[i].z);
            }

            // Normalize the weights:
            for (int i = 0; i < nSamples; i++)
            {
                m_Kernel[i].x /= sum.x;
                m_Kernel[i].y /= sum.y;
                m_Kernel[i].z /= sum.z;
            }

            // Tweak them using the desired strength. The first one is:
            //     lerp(1.0, kernel[0].rgb, strength)
            m_Kernel[0].x = (1.0f - strength.x) * 1.0f + strength.x * m_Kernel[0].x;
            m_Kernel[0].y = (1.0f - strength.y) * 1.0f + strength.y * m_Kernel[0].y;
            m_Kernel[0].z = (1.0f - strength.z) * 1.0f + strength.z * m_Kernel[0].z;

            // The others:
            //     lerp(0.0, kernel[0].rgb, strength)
            for (int i = 1; i < nSamples; i++) {
                m_Kernel[i].x *= strength.x;
                m_Kernel[i].y *= strength.y;
                m_Kernel[i].z *= strength.z;
            }

            // Finally, set 'em!
            m_Material.SetVectorArray(_KernelId, m_Kernel);
        }

        #endregion

        /// <summary>
        /// Disposes used resources.
        /// </summary>
        public void Dispose()
        {
            m_TempTarget?.Release();
            m_SpecularTarget?.Release();
        }
    }

    // [Range(0.0f, 1.0f)]
    // public float m_SSSWidth = 0.0f;
    // public bool m_FollowSurface = false;
    // public Color m_Strength = new Color(0.48f, 0.41f, 0.28f);
    // public Color m_Falloff = new Color(1.0f, 0.37f, 0.3f);

    public Shader m_Shader;

    Material m_Material;
    SeparableSSSRenderPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_Material = CoreUtils.CreateEngineMaterial(m_Shader);

        // float sssLevel = 0.025f * m_SSSWidth;
        m_ScriptablePass = new SeparableSSSRenderPass(m_Material);

        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            m_ScriptablePass.Setup(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game && m_Shader != null && m_Material != null)
            renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }
}
