Shader "Hidden/Custom/Sobel"
{
    Properties
    {
        _OutlineColor        ("Outline color", Color) = (0, 0, 0, 0)
        _OutlineThickness    ("Outlines thickness", Range(0.0001, 0.01)) = 0.0015
        _DepthSensitivity    ("Depth edge sensitivity", Range(0.0, 10.0)) = 1.0
        _NormalSensitivity   ("Normal edge sensitivity", Range(0.0, 10.0)) = 1.0
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
            Name "Sobel fullscreen edge detection"

            HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float  _OutlineThickness;
                float  _DepthSensitivity;
                float  _NormalSensitivity;
            CBUFFER_END

            static const float2 kSamples[9] = {
                float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0),
                float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0),
                float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0)
            };

            static const float kSobelX[9] = {
                 1.0,  0.0, -1.0,
                 2.0,  0.0, -2.0,
                 1.0,  0.0, -1.0
            };

            static const float kSobelY[9] = {
                 1.0,  2.0,  1.0,
                 0.0,  0.0,  0.0,
                -1.0, -2.0, -1.0
            };

            float SobelColor(float2 uv)
            {
                float2 gradR = float2(0.0, 0.0);
                float2 gradG = float2(0.0, 0.0);
                float2 gradB = float2(0.0, 0.0);

                [unroll]
                for (int i = 0; i < 9; i++)
                {
                    float2 offsetUV = uv + kSamples[i] * _OutlineThickness;
                    float3 rgb = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, offsetUV).rgb;

                    float2 kernel = float2(kSobelX[i], kSobelY[i]);
                    gradR += rgb.r * kernel;
                    gradG += rgb.g * kernel;
                    gradB += rgb.b * kernel;
                }

                float edgeColor = max(length(gradR), max(length(gradG), length(gradB)));
                return edgeColor;
            }

            float SobelDepth(float2 uv)
            {
                float2 grad = float2(0.0, 0.0);

                [unroll]
                for (int i = 0; i < 9; i++)
                {
                    float2 offsetUV = uv + kSamples[i] * _OutlineThickness;
                    float depthSample = SampleSceneDepth(offsetUV);

                    grad += depthSample * float2(kSobelX[i], kSobelY[i]);
                }

                float edgeDepth = length(grad);
                return edgeDepth;
            }

            float3 GetWorldNormal(float2 uv)
            {
                float3 encN = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv).xyz;
                return encN * 2.0 - 1.0;
            }

            float SobelNormal(float2 uv)
            {
                float2 gradNX = float2(0.0, 0.0);
                float2 gradNY = float2(0.0, 0.0);
                float2 gradNZ = float2(0.0, 0.0);

                [unroll]
                for (int i = 0; i < 9; i++)
                {
                    float2 offsetUV = uv + kSamples[i] * _OutlineThickness;

                    float3 nWS = GetWorldNormal(offsetUV);

                    float2 kernel = float2(kSobelX[i], kSobelY[i]);
                    gradNX += nWS.x * kernel;
                    gradNY += nWS.y * kernel;
                    gradNZ += nWS.z * kernel;
                }

                float lenX = length(gradNX);
                float lenY = length(gradNY);
                float lenZ = length(gradNZ);
                float edgeNormal = max(lenX, max(lenY, lenZ));

                return edgeNormal;
            }

            float4 SobelFrag (Varyings input) : SV_Target
            {
                float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
                float3 srcRGB = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float colorEdge  = SobelColor(uv);
                float depthEdge  = SobelDepth(uv)   * _DepthSensitivity;
                float normalEdge = SobelNormal(uv)  * _NormalSensitivity;
                float edgeStrength = max(colorEdge, max(depthEdge, normalEdge));
                float weight = smoothstep(1.0, 0.5, edgeStrength);
                float3 shaded = srcRGB * weight;
                float3 finalRGB = lerp(_OutlineColor.rgb, shaded, weight);

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
