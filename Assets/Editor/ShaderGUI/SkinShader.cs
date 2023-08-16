using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace URPGraphics.ShaderGUI
{
    public class SkinShader : UnityEditor.ShaderGUI
    {
        public override void OnGUI(UnityEditor.MaterialEditor materialEditorIn, UnityEditor.MaterialProperty[] properties)
        {
            if (materialEditorIn == null)
                throw new ArgumentNullException("materialEditorIn");

            base.OnGUI(materialEditorIn, properties);

            foreach (var obj in materialEditorIn.targets)
                SetMaterialKeywords((Material)obj);
        }

        public void SetMaterialKeywords(Material material)
        {
            // Normal Map
            if (material.HasProperty("_BumpMap"))
                CoreUtils.SetKeyword(material, "_NORMALMAP", material.GetTexture("_BumpMap"));

            // Metallic Gloss Map
            if (material.HasProperty("_RoughnessMap"))
                CoreUtils.SetKeyword(material, "_ROUGHNESSMAP", material.GetTexture("_RoughnessMap"));
        }
    }
}
