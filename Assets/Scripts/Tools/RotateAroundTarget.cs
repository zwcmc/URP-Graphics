using UnityEngine;

namespace URPGraphics.Tools
{
    [AddComponentMenu("URP-Graphics/Tools/Rotate Around Target")]
    public class RotateAroundTarget : MonoBehaviour
    {
        // Rotate around the target. If the target is null, then rotate around its own center.
        public GameObject target;
        public float speed = 16.0f;

        // Update is called once per frame
        void Update()
        {
            transform.RotateAround(target ? target.transform.position : transform.position, Vector3.up, speed * Time.deltaTime);
        }
    }
}
