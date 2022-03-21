Shader "Caustics"
{
    Properties
    {
        [Header(Caustics)]
        _CausticsTexture("Texture", 2D) = "white" {}
        _CausticsStrength("Strength", float) = 0
        _CausticsSplit("RGB Split", float) = 0

        [Header(Movement)]
        _CausticsScale("Scale", Range(0.0, 2.0)) = 0.5
        _CausticsSpeed("Speed", Range(0.0, 0.3)) = 0.5

        [Header(Masking)]
        _CausticsLuminanceMaskStrength("Luminance Mask", Range(0.0, 1.0)) = 0.0
        _CausticsFadeRadius("Fade Radius", Range(0.0, 1.0)) = 0.5
        _CausticsFadeStrength("Fade Strength", Range(0.5, 1.0)) = 1.0

        [HideInInspector] _SrcBlend("__src", float) = 2.0
        [HideInInspector] _DstBlend("__dst", float) = 0.0
    }

    SubShader
    {
        ZWrite Off

        Cull Front
        ZTest Always

        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }

        Pass
        {
            Blend One One

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            TEXTURE2D(_CausticsTexture);
            SAMPLER(sampler_CausticsTexture);

            CBUFFER_START(UnityPerMaterial)
            half _CausticsScale;
            half _CausticsSpeed;
            half _CausticsSplit;
            half _CausticsLuminanceMaskStrength;
            half _CausticsStrength;
            half _CausticsFadeRadius;
            half _CausticsFadeStrength;
            CBUFFER_END

            half4x4 _MainLightDirection;

            half2 Panner(half2 uv, half speed, half tiling)
            {
                half2 d = half2(1, 0);
                return (d * _Time.y * speed) + (uv * tiling);
            }

            half3 SampleCaustics(half2 uv, half split)
            {
                half2 uv1 = uv + half2(split, split);
                half2 uv2 = uv + half2(split, -split);
                half2 uv3 = uv + half2(-split, -split);

                half r = SAMPLE_TEXTURE2D_LOD(_CausticsTexture, sampler_CausticsTexture, uv1, 0).r;
                half g = SAMPLE_TEXTURE2D_LOD(_CausticsTexture, sampler_CausticsTexture, uv2, 0).r;
                half b = SAMPLE_TEXTURE2D_LOD(_CausticsTexture, sampler_CausticsTexture, uv3, 0).r;

                return half3(r, g, b);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // calculate position in screen-space coordinates
                float2 positionNDC = IN.positionCS.xy / _ScaledScreenParams.xy;

                // sample scene depth using screen-space coordinates
                #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(positionNDC);
                #else
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
                #endif

                // calculate position in world-space coordinates
                float3 positionWS = ComputeWorldSpacePosition(positionNDC, depth, UNITY_MATRIX_I_VP);

                // calculate caustics texture UV coordinates (influenced by light direction)
                half2 uv = mul(positionWS, _MainLightDirection).xy;

                // create panning UVs for the caustics
                half2 uv1 = Panner(uv, 0.75 * _CausticsSpeed, 1 / _CausticsScale);
                half2 uv2 = Panner(uv, 1 * _CausticsSpeed, -1 / _CausticsScale);

                // sample the caustics
                _CausticsSplit *= 0.015;
                half3 tex1 = SampleCaustics(uv1, _CausticsSplit);
                half3 tex2 = SampleCaustics(uv2, _CausticsSplit);

                // combine the caustics
                half3 caustics = min(tex1, tex2) * _CausticsStrength * 100;

                // calculate position in object-space coordinates
                float3 positionOS = TransformWorldToObject(positionWS);

                // create bounding box mask
                float boundingBoxMask = all(step(positionOS, 0.5) * (1 - step(positionOS, -0.5)));

                // edge fade mask
             
                half sphereMask = 1 - saturate((distance(positionOS, 0) - _CausticsFadeRadius) / (1 - _CausticsFadeStrength));
                // 1 - saturate((distance(Coords, Center) - Radius) / (1 - Hardness));
                half edgeFadeMask = sphereMask;// = smoothstep(0, _CausticsFade, mask);
                
                // luminance mask
                half3 sceneColor = SampleSceneColor(positionNDC);
                half sceneLuminance = Luminance(sceneColor);
                //half luminanceMask = smoothstep(_CausticsLuminanceMaskStrength, _CausticsLuminanceMaskStrength + 0.1, sceneLuminance);
                half luminanceMask = lerp(1, sceneLuminance, _CausticsLuminanceMaskStrength);

                // mask the caustics
                caustics *= boundingBoxMask;
                caustics *= edgeFadeMask;
                caustics *= luminanceMask;

                return half4(caustics, 1.0);
            }
            ENDHLSL
        }
    }
}