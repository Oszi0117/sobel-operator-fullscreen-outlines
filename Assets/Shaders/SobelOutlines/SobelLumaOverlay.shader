Shader "Oszi/Fullscreen/SobelLumaOverlay"
{
    Properties
    {
        _EdgeColor ("Edge color", Color) = (1,1,1,1)
        _EdgeStrength ("Edge strength", Range(0,10)) = 2.0
        _Threshold ("Edge threshold", Range(0,1)) = 0.2
        _OverlayOriginal ("Overlay original (0 = edges only, 1 = overlay)", Range(0,1)) = 1.0
        _LumaValues ("Custom luma values", Vector) = (0.299, 0.587, 0.114, 0.0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque"
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
            #include "Assets/Shaders/SobelOutlines/SobelKernels.hlsl"

            //GLOBAL VARIABLES
            float _ScanProgress;
            float _UseScan;
            float _ScanRange;
            float _ScanSoftness;
            float _ScanLineWidth;
            float _ScanCurvePower;
            float _ScanEdgeBoost;

            CBUFFER_START(UnityPerMaterial)
                float4 _EdgeColor;
                float _EdgeStrength;
                float _Threshold;
                float _OverlayOriginal;
                float3 _LumaValues;
            CBUFFER_END

            float4 sobel_frag(Varyings input) : SV_Target
            {
                float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
                float2 texel = _BlitTexture_TexelSize.xy;

                float2 grad_l = 0;
                float2 grad_d = 0;

                [unroll] //unrolling since the number of iterations is const
                for (int i = 0; i < 9; i++)
                {
                    float2 uv_offset = uv + texel * k_samples[i];
                    float3 source_color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv_offset).rgb;
                    float luma = dot(source_color, _LumaValues);
                    float depth = LinearEyeDepth(SampleSceneDepth(uv_offset), _ZBufferParams);
                    float2 kernel = float2(k_sobel_x[i], k_sobel_y[i]);

                    grad_l += luma * kernel;
                    grad_d += depth * kernel;
                }

                float mag_color = length(grad_l);
                float mag_depth = length(grad_d);

                float edge_color = saturate(_EdgeStrength * mag_color - _Threshold);
                float edge_depth = saturate(_EdgeStrength * mag_depth - _Threshold);
                float edge_val = saturate(max(edge_color, edge_depth));

                float3 edge_rgb = edge_val * _EdgeColor.rgb;

                float3 source_color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 overlay_rgb = saturate(source_color + edge_rgb);
                float3 final_rgb = lerp(edge_rgb, overlay_rgb, _OverlayOriginal);

                float depth = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);

                float scan_dist = saturate(_ScanProgress) * _ScanRange;
                float cutoff_base = max(_ScanRange - scan_dist, 0.0);
                float edge_x = abs(uv.x - 0.5) * 2.0;
                float curve01 = pow(edge_x, _ScanCurvePower);
                float cutoff_scale = lerp(1.0, _ScanEdgeBoost, curve01);
                float cutoff = cutoff_base * cutoff_scale;

                float mask_fill = smoothstep(cutoff - _ScanSoftness, cutoff + _ScanSoftness, depth);
                float3 scanned_rgb = lerp(source_color, final_rgb, mask_fill);
                float3 filled = lerp(final_rgb, scanned_rgb, step(0.5, _UseScan));

                float line_w = max(_ScanLineWidth, 1e-4);
                float line_mask = (1.0 - saturate(abs(depth - cutoff) / line_w)) * step(0.5, _UseScan);
                float3 final_ring_rgb = lerp(filled, final_rgb, line_mask);

                return float4(final_ring_rgb, 1.0);
            }
            ENDHLSL

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment sobel_frag
            ENDHLSL
        }
    }

    FallBack Off
}