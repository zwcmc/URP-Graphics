using UnityEngine;

namespace URPGraphics.Tools
{
    [AddComponentMenu("URP-Graphics/Tools/Random Move")]
    public class RandomMove : MonoBehaviour
    {
        public float radius = 5.0f;

        [Range(0.1f, 100.0f)]
        public float speed = 16.0f;

        private int _randomSeed = 0;
        private Vector3 _targetPosition;
        private Vector3 _currentPosition;
        private float _moveTime;
        private float _time;

        // Start is called before the first frame update
        void Start()
        {
            ResetPosition();
        }

        void ResetPosition()
        {
            Random.InitState(_randomSeed++);
            var pos = Random.insideUnitCircle * radius;
            Vector3 transformPosition = transform.position;
            _targetPosition = new Vector3(pos.x, transformPosition.y, pos.y);
            _currentPosition = transformPosition;
            _moveTime = 10.0f / speed * Vector3.Distance(_targetPosition, _currentPosition);
            _time = 0.0f;
        }

        // Update is called once per frame
        void Update()
        {
            _time += Time.deltaTime;
            if (_time > _moveTime) ResetPosition();

            float lerpValue = _time / _moveTime;
            transform.position = Vector3.Lerp(_currentPosition, _targetPosition, lerpValue);
        }
    }
}
