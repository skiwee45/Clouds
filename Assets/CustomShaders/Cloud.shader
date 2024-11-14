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
        Blend SrcAlpha OneMinusSrcAlpha // Additive blending
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "LightMode" = "ForwardBase" }
        
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            // Maximum number of raymarching samples
            #define MAX_STEP_COUNT 128
            // #define PI 3.14159265359

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

            //constants
            static const float PI = 3.14159265359;

            // axis aligned bounding box
            // never returns negative distance
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

            float hg(float cosTheta, float g)
            {
                // with a g=0.5, range is 0.02 (cam and sun same dir) to 0.48 (cloud between cam and sun)
                float g2 = g*g;
                return (1 - g2) / pow(1 + g2 - 2*g*cosTheta, 1.5) / (4 * PI);
            }

            float lightMarch(float3 position)
            {
                float3 dirToLight = _WorldSpaceLightPos0.xyz; // direction TO light, this needs forward rendering mode
                float distInBox = intersectAABB(position, dirToLight, float3(-2, -2, -2) / 2, float3(2, 2, 2) / 2).y;
                float stepSize = distInBox / 10;
                float totalDensity = 0;
                for (int step = 0; step < 10; step++) {
                    float density = tex3D(_CloudTexture, position + float3(0.5, 0.5, 0.5)).r;
                    totalDensity += density * stepSize;
                    position += dirToLight * stepSize;
                }
                float transmittance = beerPowder(totalDensity * 10  ); // use beer powder here because this is light
                return 0.2 + transmittance * 0.8; // hard coded for now
            }

            fixed4 frag (v2f p) : SV_Target
            {
                // TODO: for some reason, camera inside the box makes cloud much darker
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;
                float3 rayDir = normalize(p.worldPos - rayOrigin);
                float2 t = intersectAABB(rayOrigin, rayDir, float3(-1, -1, -1) / 2, float3(1, 1, 1) / 2);
                float distToBox = t.x;
                float distInBox = t.y;
                float3 currentPosition = rayOrigin + rayDir * distToBox;
                float stepSize = _StepSize;
                float totalDistance = 0;
                float lightEnergy = 0.5;
                float transmittance = 1;
                
                int stepCount = 0;
                int maxSteps = 100;
                while (totalDistance < distInBox) {
                    stepCount++;

                    // sample textures is from (0,0,0) to (1,1,1)
                    float density = tex3D(_CloudTexture, currentPosition + float3(0.5, 0.5, 0.5)).r;// currently hard coded for unit cube
                
                    float currentTransmittance = beer(density * stepSize * 2); //multiplier hard coded
                    float luminance = lightMarch(currentPosition);
                    lightEnergy += luminance * density * stepSize * transmittance;
                    transmittance *= currentTransmittance;
                
                    if (stepCount >= maxSteps) {
                        break;
                    }
                    
                    totalDistance += stepSize;
                    currentPosition += rayDir * stepSize;
                }
                float cosAngle = dot(rayDir, _WorldSpaceLightPos0.xyz);
                float phase = hg(cosAngle, 0.5) * 0.5 + 0.95; // TODO: tweak
                lightEnergy *= phase;
                float alpha = 1 - transmittance;
                float4 finalColor = _CloudColor * lightEnergy + _BaseColor * (1 - lightEnergy);
                return fixed4(finalColor.rgb, alpha);
            }
            ENDCG
        }
    }
}