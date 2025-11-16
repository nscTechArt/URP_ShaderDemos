Shader "Custom/SimpleLitParallax"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Map", 2D) = "white" {}
        [Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        
        [NoScaleOffset] _ParallaxMap ("Parallax Map", 2D) = "black" {}
        _ParallaxIntensity ("Parallax Intensity", Range(0.0, 0.1)) = 0.02
        _ParallaxSteps ("Parallax Steps", Integer) = 10
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment PassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #define PARALLAX_OFFSET_LIMITING 1
            #define PARALLAX_BIAS 0.0

            struct Attributes
            {
                float4 positionOS     : POSITION;
                float3 normalOS       : NORMAL;
                float4 tangentOS      : TANGENT;
                float2 texcoord       : TEXCOORD0;
                float3 viewDirTS      : TEXCOORD1; 
            };

            struct Varyings
            {
                float4 positionHCS    : SV_POSITION;
                float3 normalWS       : TEXCOORD0;
                float3 positionWS     : TEXCOORD1;
                float2 uv             : TEXCOORD2;
                float3 tangentWS      : TEXCOORD3;
                float3 bitangentWS    : TEXCOORD4;
                float3 viewDirTS      : VAR_VIEWDIR_TS;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _Smoothness;
                half _Metallic;
                float _BumpScale;
                float _ParallaxIntensity;
                int _ParallaxSteps;
            CBUFFER_END

            half3 NormalTangentToWorld(half3 normalTS, half3 normalWS, half3 tangentWS, half3 bitangentWS)
            {
                half3x3 TBN = half3x3(tangentWS, bitangentWS, normalWS);
                return normalize(mul(normalTS, TBN));
            }

            inline float3 GetViewDirOS(float4 positionOS)
            {
                float3 cameraPosOS = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos.xyz, 1)).xyz;
                return cameraPosOS - positionOS.xyz;
            }

            Varyings PassVertex(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionHCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInput.normalWS;
                output.tangentWS = normalInput.tangentWS;
                output.bitangentWS = normalInput.bitangentWS;

                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

                float3x3 objectToTangent = float3x3(
                    input.tangentOS.xyz,
                    cross(input.normalOS, input.tangentOS.xyz) * input.tangentOS.w,
                    input.normalOS);
                output.viewDirTS = mul(objectToTangent, GetViewDirOS(input.positionOS));
    
                return output;
            }

            float GetParallaxHeight(float2 uv)
            {
                return SAMPLE_TEXTURE2D(_ParallaxMap, sampler_ParallaxMap, uv).g;
            }

            float2 ParallaxOffset(float2 uv, float2 viewDir)
            {
                float height = GetParallaxHeight(uv);
                height -= 0.5;
                height *= _ParallaxIntensity;
                return viewDir * height;
            }
            
            float2 ParallaxRaymarching (float2 uv, float2 viewDir)
            {
				#if !defined(PARALLAX_RAYMARCHING_STEPS)
					#define PARALLAX_RAYMARCHING_STEPS 10
				#endif
            	
				float2 uvOffset = 0;
				float stepSize = 1.0 / PARALLAX_RAYMARCHING_STEPS;
				float2 uvDelta = viewDir * (stepSize * _ParallaxIntensity);

				float stepHeight = 1;
				float surfaceHeight = GetParallaxHeight(uv);

				float2 prevUVOffset = uvOffset;
				float prevStepHeight = stepHeight;
				float prevSurfaceHeight = surfaceHeight;

				for (int i = 1; i < PARALLAX_RAYMARCHING_STEPS && stepHeight > surfaceHeight; i++)
				{
					prevUVOffset = uvOffset;
					prevStepHeight = stepHeight;
					prevSurfaceHeight = surfaceHeight;
					
					uvOffset -= uvDelta;
					stepHeight -= stepSize;
					surfaceHeight = GetParallaxHeight(uv + uvOffset);
				}

				#if !defined(PARALLAX_RAYMARCHING_SEARCH_STEPS)
					#define PARALLAX_RAYMARCHING_SEARCH_STEPS 0
				#endif
				#if PARALLAX_RAYMARCHING_SEARCH_STEPS > 0
					for (int i = 0; i < PARALLAX_RAYMARCHING_SEARCH_STEPS; i++) {
						uvDelta *= 0.5;
						stepSize *= 0.5;

						if (stepHeight < surfaceHeight) {
							uvOffset += uvDelta;
							stepHeight += stepSize;
						}
						else {
							uvOffset -= uvDelta;
							stepHeight -= stepSize;
						}
						surfaceHeight = GetParallaxHeight(uv + uvOffset);
					}
				#elif defined(PARALLAX_RAYMARCHING_INTERPOLATE)
					float prevDifference = prevStepHeight - prevSurfaceHeight;
					float difference = surfaceHeight - stepHeight;
					float t = prevDifference / (prevDifference + difference);
					uvOffset = prevUVOffset - uvDelta * t;
				#endif

				return uvOffset;
			}

            void ApplyParallax(inout Varyings input)
            {
                input.viewDirTS = normalize(input.viewDirTS);
                #if PARALLAX_OFFSET_LIMITING
                    input.viewDirTS.xy /= input.viewDirTS.z + PARALLAX_BIAS;
                #endif
                
                float2 uvOffset = ParallaxRaymarching(input.uv, input.viewDirTS.xy);
                
                input.uv.xy += uvOffset;
            }

            half4 PassFragment(Varyings input) : SV_Target
            {
                ApplyParallax(input);
                
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;

                half4 normalSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv);
                half3 normalTS = UnpackNormalScale(normalSample, _BumpScale);
                normalTS = normalize(normalTS);
                
                half3 normalWS = NormalTangentToWorld(normalTS, input.normalWS, input.tangentWS, input.bitangentWS);

                InputData lightingInput = (InputData)0;
                lightingInput.positionWS = input.positionWS;
                lightingInput.normalWS = normalWS;
                lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);

                SurfaceData surfaceData;
                surfaceData.albedo = baseColor.rgb;
                surfaceData.alpha = baseColor.a;
                surfaceData.metallic = _Metallic;
                surfaceData.specular = half3(0.0h, 0.0h, 0.0h);
                surfaceData.smoothness = _Smoothness;
                surfaceData.normalTS = normalTS;
                surfaceData.occlusion = 1.0;
                surfaceData.emission = half3(0, 0, 0);
                surfaceData.clearCoatMask = 0.0h;
                surfaceData.clearCoatSmoothness = 0.0h;

                half4 color = UniversalFragmentPBR(lightingInput, surfaceData);
                
                return color;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}