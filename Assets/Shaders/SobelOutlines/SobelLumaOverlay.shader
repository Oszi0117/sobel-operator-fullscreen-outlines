Shader "Hidden/Custom/SobelLumaOverlay"
{
    Properties
    {
        _EdgeColor        ("Edge Color", Color) = (1,1,1,1)
        _EdgeStrength     ("Edge Strength", Range(0,10)) = 2.0
        _EdgeThickness      ("Edge Thickness", Range(0.1,1)) = 0.1
        _Threshold          ("Edge Threshold", Range(0,1))  = 0.2
        _OverlayOriginal  ("Overlay Original (0 = edges only, 1 = overlay)", Range(0,1)) = 1.0
        _LumaValues ("Custom luma values", Vector) = (0.299, 0.587, 0.114, 0.0)
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

            CBUFFER_START(UnityPerMaterial)
                float4 _EdgeColor;
                float  _EdgeStrength;
                float  _Threshold;
                float  _OverlayOriginal;
                float3 _LumaValues;
                float _EdgeThickness;
            CBUFFER_END

            inline float Luma(float3 rgb)
            {
                return dot(rgb, _LumaValues);
            }

            void SobelMat3x3(
                float tl, float tc, float tr,
                float ml, float mc, float mr,
                float bl, float bc, float br,
                out float magnitude)
            {

                //skipping zeros
                float gx =
                    (-1.0 * tl) + /* (0.0 * tc) */ + (1.0 * tr) +
                    (-2.0 * ml) + /* (0.0 * mc) */ + (2.0 * mr) +
                    (-1.0 * bl) + /* (0.0 * bc) */ + (1.0 * br);

                float gy =
                    (-1.0 * tl) + (-2.0 * tc) + (-1.0 * tr) +
                    //(0.0 * ml)  + (0.0 * mc)  + (-1.0 * mr) +
                    (1.0 * bl)  + (2.0 * bc)  + (1.0 * br);

                magnitude = sqrt(gx * gx + gy * gy);
            }

            float4 SobelFrag (Varyings input) : SV_Target
            {
                float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

                // one-pixel step in UV space
                float2 texel = _BlitTexture_TexelSize.xy;

                //COLOR BRIGHTNESS
                //https://docs.unity3d.com/Packages/com.unity.visualeffectgraph@10.2/manual/Operator-ColorLuma.html

                float lumTL = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2(-1,-1)).rgb);
                float lumTC = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 0,-1)).rgb);
                float lumTR = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2( 1,-1)).rgb);

                float lumML = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + texel * float2(-1, 0)).rgb);
                float lumMC = Luma(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb);
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

                //DEPTH
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

                //edge color
                float3 edgeRGB = edgeVal * _EdgeColor.rgb;

                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 overlayRGB = saturate(src + edgeRGB);

                float3 finalRGB = lerp(edgeRGB, overlayRGB, _OverlayOriginal);

                return float4(finalRGB, 1.0);
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
