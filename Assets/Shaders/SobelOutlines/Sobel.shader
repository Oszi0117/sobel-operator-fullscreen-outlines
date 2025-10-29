Shader "Oszi/Fullscreen/SobelCDN"
{
    Properties
    {
        _EdgeColor ("Edge color", Color) = (0, 0, 0, 0)
        _EdgeThickness ("Edge thickness", Range(0.0001, 0.01)) = 0.0015
        _DepthSensitivity ("Depth edge sensitivity", Range(0.0, 10.0)) = 10.0
        _NormalSensitivity ("Normal edge sensitivity", Range(0.0, 10.0)) = 0.25
        [Toggle] _UseDistanceFade ("Use distance fade", Float) = 1
        _FadeStart ("Edge fade start distance", Range(0.0, 200.0)) = 5.0
        _FadeEnd ("Edge fade end distance", Range(0.0, 200.0)) = 50.0
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
            Name "Sobel color, depth, normal fullscreen edge detection"

            HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
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
                float _EdgeThickness;
                float _DepthSensitivity;
                float _NormalSensitivity;
                float _UseDistanceFade;
                float _FadeStart;
                float _FadeEnd;
            CBUFFER_END

            float4 sobel_frag(Varyings input) : SV_Target
            {
                float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
                float3 source_color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                float2 color_gradient_r = 0;
                float2 color_gradient_g = 0;
                float2 color_gradient_b = 0;
                float2 normal_gradient_x = 0;
                float2 normal_gradient_y = 0;
                float2 normal_gradient_z = 0;
                float2 depth_gradient = 0;

                [unroll] //unrolling since the number of iterations is const
                for (int i = 0; i < 9; i++)
                {
                    float2 uv_offset = uv + k_samples[i] * _EdgeThickness;
                    float3 rgb = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv_offset).rgb;
                    float depth = SampleSceneDepth(uv_offset);
                    float3 normal = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv_offset).xyz * 2.0 - 1.0;
                    float2 kernel = float2(k_sobel_x[i], k_sobel_y[i]);

                    color_gradient_r += rgb.r * kernel;
                    color_gradient_g += rgb.g * kernel;
                    color_gradient_b += rgb.b * kernel;

                    depth_gradient += depth * kernel;

                    normal_gradient_x += normal.x * kernel;
                    normal_gradient_y += normal.y * kernel;
                    normal_gradient_z += normal.z * kernel;
                }

                float color_edge = max(length(color_gradient_r), max(length(color_gradient_g), length(color_gradient_b)));
                float depth_edge = length(depth_gradient) * _DepthSensitivity;
                float normal_edge = max(length(normal_gradient_x), max(length(normal_gradient_y), length(normal_gradient_z))) * _NormalSensitivity;

                float edge_strength = max(color_edge, max(depth_edge, normal_edge));
                float weight = smoothstep(1.0, 0.5, edge_strength);

                float raw_depth = SampleSceneDepth(uv);
                float linear_dist = LinearEyeDepth(raw_depth, _ZBufferParams);

                float denom = max(_FadeEnd - _FadeStart, 1e-4);
                float fade_factor = saturate((_FadeEnd - linear_dist) / denom);
                float faded_weight = lerp(1.0, weight, fade_factor);
                float dist_weighted = lerp(weight, faded_weight, step(0.5, _UseDistanceFade));

                float scan_dist = saturate(_ScanProgress) * _ScanRange;
                float cutoff_base = max(_ScanRange - scan_dist, 0.0);
                float edge_x = abs(uv.x - 0.5) * 2.0;
                float curve01 = pow(edge_x, _ScanCurvePower);
                float cutoff_scale = lerp(1.0, _ScanEdgeBoost, curve01);
                float cutoff = cutoff_base * cutoff_scale;

                float mask_fill = smoothstep(cutoff - _ScanSoftness, cutoff + _ScanSoftness, linear_dist);
                float scanned_weight = lerp(1.0, dist_weighted, mask_fill);
                float final_scanned_weight = lerp(dist_weighted, scanned_weight, step(0.5, _UseScan));

                float line_w = max(_ScanLineWidth, 1e-4);
                float line_mask = (1.0 - saturate(abs(linear_dist - cutoff) / line_w)) * step(0.5, _UseScan);

                float outlined_weight = lerp(final_scanned_weight, 0.0, line_mask);

                float3 shaded = source_color * outlined_weight;
                float3 final_rgb = lerp(_EdgeColor.rgb, shaded, outlined_weight);
                return float4(final_rgb, 1.0);
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