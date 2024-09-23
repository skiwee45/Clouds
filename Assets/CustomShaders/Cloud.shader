Shader "Unlit/Cloud"
{
    Properties
    {
        _CloudColor ("Cloud Color", Color) = (1, 1, 1, 1)
        _BaseColor ("Base Color", Color) = (0.1, 0.1, 0.1, 1)
        _CloudTexture ("Cloud Texture", 3D) = "white" {}
        _StepSize ("Step Size", Range(0.01, 0.15)) = 0.02
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always
        Blend One OneMinusSrcAlpha // Additive blending
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "LightMode" = "ForwardBase" }
        
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            // Maximum number of raymarching samples
            #define MAX_STEP_COUNT 128

            struct meshdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD1;
            };

            v2f vert (meshdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            //properties
            fixed4 _CloudColor;
            fixed4 _BaseColor;
            sampler3D _CloudTexture;
            float _StepSize;

            float2 intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax) {
                float3 tMin = (boxMin - rayOrigin) / rayDir;
                float3 tMax = (boxMax - rayOrigin) / rayDir;
                float3 t1 = min(tMin, tMax);
                float3 t2 = max(tMin, tMax);
                float tNear = max(max(t1.x, t1.y), t1.z);
                float tFar = min(min(t2.x, t2.y), t2.z);
                float dstToBox = max(0, tNear);
                float dstInsideBox = max(0, tFar - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            half beer(float dst) {
                return exp(-dst * 1);
            }

            half powder(float dst) {
                return 1 - exp(-dst * 2);
            }

            half beerPowder(float dst) {
                return beer(dst) * powder(dst);
            }

            float lightMarch(float3 position)
            {
                float3 dirToLight = _WorldSpaceLightPos0.xyz; // direction to light, this needs forward rendering mode
                float distInBox = intersectAABB(position, dirToLight, float3(-1, -1, -1) / 2, float3(1, 1, 1) / 2).y;
                float stepSize = distInBox / 10;
                float totalDensity = 0;
                for (int step = 0; step < 10; step++) {
                    float density = tex3D(_CloudTexture, position + float3(0.5, 0.5, 0.5)).r;
                    totalDensity += density * stepSize;
                    position += dirToLight * stepSize;
                }
                float transmittance = beer(totalDensity * 3);
                return 0.2 + transmittance * 0.8; // hard coded for now
            }

            fixed4 frag (v2f p) : SV_Target
            {
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;
                float3 rayDir = normalize(p.worldPos - rayOrigin);
                float2 t = intersectAABB(rayOrigin, rayDir, float3(-1, -1, -1) / 2, float3(1, 1, 1) / 2);
                float distToBox = t.x;
                float distInBox = t.y;
                float3 currentPosition = rayOrigin + rayDir * distToBox;
                float stepSize = _StepSize;
                float totalDistance = 0;
                float lightEnergy = 0;
                float totalDensity = 0;
                
                int stepCount = 0;
                while (totalDistance < distInBox) {
                    int maxSteps = 100;
                    // currently hard coded for unit cube
                    stepCount++;
                    float density = tex3D(_CloudTexture, currentPosition + float3(0.5, 0.5, 0.5)).r;
                    totalDensity += density * stepSize;
                
                    float currentTransmittance = beerPowder(totalDensity);
                    float lightTransmittance = lightMarch(currentPosition);
                    lightEnergy += lightTransmittance * density * stepSize * currentTransmittance;
                
                    if (stepCount >= maxSteps) {
                        break;
                    }
                    
                    totalDistance += stepSize;
                    currentPosition += rayDir * stepSize;
                }
                //TODO: shadows are not quite right yet
                return _CloudColor * lightEnergy + _BaseColor * (1 - beer(totalDensity));
            }
            ENDCG
        }
    }
}