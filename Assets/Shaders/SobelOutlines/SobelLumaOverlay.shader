Shader "Hidden/Custom/SobelLumaOverlay"
{
    Properties
    {
        _EdgeColor        ("Edge Color", Color) = (1,1,1,1)
        _EdgeStrength     ("Edge Strength", Range(0,10)) = 2.0
        _EdgeThickness    ("Edge Thickness", Range(0.1,1)) = 0.1
        _Threshold        ("Edge Threshold", Range(0,1))  = 0.2
        _OverlayOriginal  ("Overlay Original (0 = edges only, 1 = overlay)", Range(0,1)) = 1.0
        _LumaValues       ("Custom luma values", Vector) = (0.299, 0.587, 0.114, 0.0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
        }

        Cull Off
        ZWrite Off
        ZTest Always
        Blend One Zero

        Pass
        {
            Name "Sobel luma overlay"

            HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            float _ScanProgress;
            float _UseScan;
            float _ScanRange;
            float _ScanSoftness;
            float _ScanLineWidth;
            float _ScanCurvePower;
            float _ScanEdgeBoost;

            CBUFFER_START(UnityPerMaterial)
                float4 _EdgeColor;
                float  _EdgeStrength;
                float  _Threshold;
                float  _OverlayOriginal;
                float3 _LumaValues;
                float  _EdgeThickness;
            CBUFFER_END

            float Luma(float3 rgb)
            {
                return dot(rgb, _LumaValues);
            }

            void SobelMat3x3(
                float tl, float tc, float tr,
                float ml, float mc, float mr,
                float bl, float bc, float br,
                out float magnitude)
            {
                float gx =
                    (-1.0 * tl) + (1.0 * tr) +
                    (-2.0 * ml) + (2.0 * mr) +
                    (-1.0 * bl) + (1.0 * br);

                float gy =
                    (-1.0 * tl) + (-2.0 * tc) + (-1.0 * tr) +
                    ( 1.0 * bl) + ( 2.0 * bc) + ( 1.0 * br);

                magnitude = sqrt(gx * gx + gy * gy);
            }

            float4 SobelFrag (Varyings input) : SV_Target
            {
                float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

                float2 texel = _BlitTexture_TexelSize.xy;

                float lumTL = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2(-1,-1)).rgb);
                float lumTC = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 0,-1)).rgb);
                float lumTR = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 1,-1)).rgb);

                float lumML = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2(-1, 0)).rgb);
                float lumMC = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv                             ).rgb);
                float lumMR = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 1, 0)).rgb);

                float lumBL = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2(-1, 1)).rgb);
                float lumBC = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 0, 1)).rgb);
                float lumBR = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 1, 1)).rgb);

                float magColor;
                SobelMat3x3(
                    lumTL, lumTC, lumTR,
                    lumML, lumMC, lumMR,
                    lumBL, lumBC, lumBR,
                    magColor
                );

                float depthTL = LinearEyeDepth(SampleSceneDepth(uv + texel * float2(-1,-1)), _ZBufferParams);
                float depthTC = LinearEyeDepth(SampleSceneDepth(uv + texel * float2( 0,-1)), _ZBufferParams);
                float depthTR = LinearEyeDepth(SampleSceneDepth(uv + texel * float2( 1,-1)), _ZBufferParams);

                float depthML = LinearEyeDepth(SampleSceneDepth(uv + texel * float2(-1, 0)), _ZBufferParams);
                float depthMC = LinearEyeDepth(SampleSceneDepth(uv                             ), _ZBufferParams);
                float depthMR = LinearEyeDepth(SampleSceneDepth(uv + texel * float2( 1, 0)), _ZBufferParams);

                float depthBL = LinearEyeDepth(SampleSceneDepth(uv + texel * float2(-1, 1)), _ZBufferParams);
                float depthBC = LinearEyeDepth(SampleSceneDepth(uv + texel * float2( 0, 1)), _ZBufferParams);
                float depthBR = LinearEyeDepth(SampleSceneDepth(uv + texel * float2( 1, 1)), _ZBufferParams);

                float magDepth;
                SobelMat3x3(
                    depthTL, depthTC, depthTR,
                    depthML, depthMC, depthMR,
                    depthBL, depthBC, depthBR,
                    magDepth
                );

                float edgeColor = saturate(_EdgeStrength * magColor - _Threshold);
                float edgeDepth = saturate(_EdgeStrength * magDepth - _Threshold);

                float edgeVal  = saturate(max(edgeColor, edgeDepth));

                float3 edgeRGB = edgeVal * _EdgeColor.rgb;

                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 overlayRGB = saturate(src + edgeRGB);

                float3 finalRGB = lerp(edgeRGB, overlayRGB, _OverlayOriginal);

                float scanDist = saturate(_ScanProgress) * _ScanRange;
                float cutoffDistBase = max(_ScanRange - scanDist, 0.0);

                float edgeX = abs(uv.x - 0.5) * 2.0;
                float curve01 = pow(edgeX, _ScanCurvePower);
                float cutoffScale = lerp(1.0, _ScanEdgeBoost, curve01);
                float cutoffDist = cutoffDistBase * cutoffScale;

                float scannerMaskSoft = smoothstep(cutoffDist - _ScanSoftness, cutoffDist + _ScanSoftness, depthMC);

                float3 scannedRGB = lerp(src, finalRGB, scannerMaskSoft);

                float scanToggle = step(0.5, _UseScan);
                float3 finalScannedRGB = lerp(finalRGB, scannedRGB, scanToggle);

                float lineWidth = max(_ScanLineWidth, 1e-4);
                float lineMaskBase = 1.0 - saturate(abs(depthMC - cutoffDist) / lineWidth);
                float lineMask = lineMaskBase * scanToggle;

                float3 finalRingRGB = lerp(finalScannedRGB, finalRGB, lineMask);

                return float4(finalRingRGB, 1.0);
            }

            ENDHLSL

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment SobelFrag
            ENDHLSL
        }
    }

    FallBack Off
}
