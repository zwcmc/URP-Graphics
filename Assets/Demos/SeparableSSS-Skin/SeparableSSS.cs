using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable, VolumeComponentMenuForRenderPipeline("URP Graphics/Post-processing/SeparableSSS", typeof(UniversalRenderPipeline))]
public class SeparableSSS : VolumeComponent, IPostProcessComponent
{
    [Header("SeparableSSS")]
    public ClampedFloatParameter sSSWidth = new ClampedFloatParameter(0.0f, 0.0f, 1.0f);

    public BoolParameter followSurface = new BoolParameter(false);

    public ColorParameter strength = new ColorParameter(new Color(0.48f, 0.41f, 0.28f));

    public ColorParameter falloff = new ColorParameter(new Color(1.0f, 0.37f, 0.3f));

    /// <inheritdoc/>
    public bool IsActive() => sSSWidth.value > 0.0f;

    /// <inheritdoc/>
    public bool IsTileCompatible() => false;
}
