Shader "Universal Render Pipeline/Custom/SimpleProceduralMask"
{
    Properties
    {
        [Header(Mask Settings)]
        [Toggle]_EnableU ("Enable U Mask", Float) = 1
        [Toggle]_InvertU ("Invert U", Float) = 0
        _UPosition ("U Position", Range(0, 1)) = 0.5
        _UHardness ("U Hardness", Range(0, 1)) = 0.5
        
        [Toggle]_EnableV ("Enable V Mask", Float) = 1
        [Toggle]_InvertV ("Invert V", Float) = 0
        _VPosition ("V Position", Range(0, 1)) = 0.5
        _VHardness ("V Hardness", Range(0, 1)) = 0.5
        
        _BlendMode ("Blend Mode", Range(0, 2)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float _EnableU;
                float _InvertU;
                float _UPosition;
                float _UHardness;
                float _EnableV;
                float _InvertV;
                float _VPosition;
                float _VHardness;
                float _BlendMode;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            float CalculateMask(float coord, float position, float hardness, float invert)
            {
                float mask = 0;
                
                if (invert < 0.5)
                {
                    mask = 1.0 - smoothstep(position - hardness * 0.5, 
                                           position + hardness * 0.5, 
                                           coord);
                }
                else
                {
                    mask = smoothstep(position - hardness * 0.5, 
                                     position + hardness * 0.5, 
                                     coord);
                }
                
                return mask;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float uMask = 1.0;
                float vMask = 1.0;
                float finalMask = 1.0;
                
                if (_EnableU > 0.5)
                {
                    uMask = CalculateMask(input.uv.x, _UPosition, _UHardness, _InvertU);
                }
                
                if (_EnableV > 0.5)
                {
                    vMask = CalculateMask(input.uv.y, _VPosition, _VHardness, _InvertV);
                }
                
                if (_BlendMode < 0.5)
                {
                    finalMask = uMask * vMask;
                }
                else if (_BlendMode < 1.5)
                {
                    finalMask = saturate(uMask + vMask);
                }
                else
                {
                    finalMask = min(uMask, vMask);
                }
                
                return half4(finalMask, finalMask, finalMask, 1.0);
            }
            ENDHLSL
        }
    }
}