using Cysharp.Threading.Tasks;
using System;
using UnityEngine;
using UnityEngine.InputSystem;

public class InvertedScannerController : MonoBehaviour
{
    [SerializeField] bool _useScanner = true;
    [SerializeField, Range(0,1)] float _scannerProgress = 1.0f;
    [SerializeField] float _scanRangeInMeters = 10.0f;
    [SerializeField] float _scanSoftness = 5.0f;
    [SerializeField] float _scanLineWidth = 0.5f;
    [SerializeField] float _scanCurvePower = 2.0f;
    [SerializeField] float _scanEdgeBoost = 0.3f;
    [SerializeField] private float _step;
    [SerializeField] private AnimationCurve _effectCurve;
    [SerializeField] private InputActionReference _runScannerEffect;
    [SerializeField] private InputActionReference _disableScannerEffect;
    [SerializeField] private float _scannerBuffer;

    private static readonly int USE_SCAN_GV = Shader.PropertyToID("_UseScan");
    private static readonly int SCAN_PROGRESS_GV = Shader.PropertyToID("_ScanProgress");
    private static readonly int SCAN_RANGE_GV = Shader.PropertyToID("_ScanRange");
    private static readonly int SCAN_SOFTNESS_GV = Shader.PropertyToID("_ScanSoftness");
    private static readonly int SCAN_WIDTH_LINE_GV = Shader.PropertyToID("_ScanLineWidth");
    private static readonly int SCAN_CURVE_POWER_GV = Shader.PropertyToID("_ScanCurvePower");
    private static readonly int SCAN_EDGE_BOOST_GV = Shader.PropertyToID("_ScanEdgeBoost");

    void OnEnable()
    {
        _runScannerEffect.action.performed += OnRunScannerPerformed;
        _runScannerEffect.action.Enable();

        _disableScannerEffect.action.performed += OnDisableScannerPerformed;
        _disableScannerEffect.action.Enable();

        Shader.SetGlobalFloat(SCAN_RANGE_GV, _scanRangeInMeters);
    }

    private void OnDisable()
    {
        _runScannerEffect.action.performed -= OnRunScannerPerformed;
        _runScannerEffect.action.Disable();

        _disableScannerEffect.action.performed -= OnDisableScannerPerformed;
        _disableScannerEffect.action.Disable();
    }

    private void Update()
    {
        Shader.SetGlobalFloat(SCAN_SOFTNESS_GV, _scanSoftness);
        Shader.SetGlobalFloat(SCAN_WIDTH_LINE_GV, _scanLineWidth);
        Shader.SetGlobalFloat(SCAN_CURVE_POWER_GV, _scanCurvePower);
        Shader.SetGlobalFloat(SCAN_EDGE_BOOST_GV, _scanEdgeBoost);
    }

    private void OnRunScannerPerformed(InputAction.CallbackContext _) => RunScanner().Forget();

    private void OnDisableScannerPerformed(InputAction.CallbackContext context) => DisableScanner().Forget();

    private async UniTaskVoid RunScanner()
    {
        Shader.SetGlobalFloat(SCAN_PROGRESS_GV, 0);
        Shader.SetGlobalFloat(USE_SCAN_GV, 1);
        _scannerBuffer = 0;

        while (_scannerBuffer < _effectCurve.keys[^1].time)
        {
            _scannerBuffer += _step;
            var scanProgress = _effectCurve.Evaluate(_scannerBuffer);
            Shader.SetGlobalFloat(SCAN_PROGRESS_GV, scanProgress);
            await UniTask.Yield();
        }
    }

    private async UniTaskVoid DisableScanner()
    {
        while (_scannerBuffer > _effectCurve.keys[0].time)
        {
            _scannerBuffer -= _step;
            var scanProgress = _effectCurve.Evaluate(_scannerBuffer);
            Shader.SetGlobalFloat(SCAN_PROGRESS_GV, scanProgress);
            await UniTask.Yield();
        }
    }
}
