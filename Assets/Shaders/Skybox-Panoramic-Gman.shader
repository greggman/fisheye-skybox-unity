// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Skybox/Panoramic-GMan" {
Properties {
    _Tint ("Tint Color", Color) = (.5, .5, .5, .5)
    [Gamma] _Exposure ("Exposure", Range(0, 8)) = 1.0
    _Rotation ("Rotation", Range(0, 360)) = 0
    _MainTex ("Spherical  (HDR)", 2D) = "grey" {}
    [KeywordEnum(6 Frames Layout, Latitude Longitude Layout, FishEye Layout)] _Mapping("Mapping", Float) = 1
    [Enum(360 Degrees, 0, 180 Degrees, 1)] _ImageType("Image Type", Float) = 0
    [Toggle] _MirrorOnBack("Mirror on Back", Float) = 0
    [Enum(None, 0, Left Right, 1, Top Bottom, 2, Right Left, 3, Bottom Top, 4)] _Layout("3D Layout", Float) = 0
    [KeywordEnum(Debug Off, Debug On)] _Debug("Debug", Float) = 0
}

SubShader {
    Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
    Cull Off ZWrite Off

    Pass {

        CGPROGRAM
        #pragma vertex vert
        #pragma fragment frag
        #pragma target 2.0
        #pragma multi_compile __ _MAPPING_6_FRAMES_LAYOUT
        #pragma multi_compile __ _MAPPING_LATITUDE_LONGITUDE_LAYOUT
        #pragma multi_compile __ _MAPPING_FISHEYE_LAYOUT
        #pragma multi_compile __ _DEBUG_DEBUG_ON

        #include "UnityCG.cginc"

        sampler2D _MainTex;
        float4 _MainTex_ST;
        float4 _MainTex_TexelSize;
        half4 _MainTex_HDR;
        half4 _Tint;
        half _Exposure;
        float _Rotation;
#ifndef _MAPPING_6_FRAMES_LAYOUT
        bool _MirrorOnBack;
        int _ImageType;
        int _Layout;
#endif

#ifdef _MAPPING_LATITUDE_LONGITUDE_LAYOUT
        inline float2 ToRadialCoords(float3 coords)
        {
            float3 normalizedCoords = normalize(coords);
            float latitude = acos(normalizedCoords.y);
            float longitude = atan2(normalizedCoords.z, normalizedCoords.x);
            float2 sphereCoords = float2(longitude, latitude) * float2(0.5/UNITY_PI, 1.0/UNITY_PI);
            return float2(0.5,1.0) - sphereCoords;
        }
#endif

#ifdef _MAPPING_FISHEYE_LAYOUT
        inline float2 ToFisheyeCoords(float3 coords)
        {
            float3 normalizedCoords = normalize(coords);

            // convert from direction (n) to texcoord (uv)
            float r = 2.0 * atan2(length(normalizedCoords.xy), abs(normalizedCoords.z)) / UNITY_PI;
            float theta = atan2(normalizedCoords.y, normalizedCoords.x * sign(normalizedCoords.z));
            float2 uv = float2(cos(theta), sin(theta)) * r * 0.5 + 0.5;
            return frac(uv * float2(2, 1));
            //float2(1.- uv.x, uv.y); //uv * float2(-1, 1);
            //return r > 1.0 || r < -1.0 ? float2(0.5, 0.5) : float2(0, 0);
            //return uv;// * float2(-1, 1) + float2(1, 0);
            //return float2(normalizedCoords.x, normalizedCoords.x) * 0.5 + 0.5;

            /*
            float2 p = float2(
                atan2(normalizedCoords.z, normalizedCoords.x),
                atan2(normalizedCoords.z, normalizedCoords.y));
            //return p / UNITY_PI * 0.5 + 0.5;
            return normalizedCoords.xy * 0.5 + 0.5; 
            */
            //return float2(1,0);
            /*
            float correction = acos((normalizedCoords.y)) / length(normalizedCoords.xz) * (1.0 / UNITY_PI);
            return (normalizedCoords.xz) * correction;
            */
            /*
            float2 unitAngle = normalize(normalizedCoords.xz);
            float elevation = acos(normalizedCoords.y);
            float fisheyeFOV = 1.0;
            float radius = elevation / fisheyeFOV;
            float2 fishCoord = unitAngle * radius;
            return float2(0.5,1.0) - fishCoord;
            */
            /*
            float latitude = normalizedCoords.y * 0.5 + 0.5;
            float longitude = atan2(normalizedCoords.z, normalizedCoords.x);
            float2 sphereCoords = float2(longitude, latitude) * float2(0.5/UNITY_PI, 1.0);///UNITY_PI);
            return float2(0.5,1.0) - sphereCoords;
            */
        }
#endif

#ifdef _MAPPING_6_FRAMES_LAYOUT
        inline float2 ToCubeCoords(float3 coords, float3 layout, float4 edgeSize, float4 faceXCoordLayouts, float4 faceYCoordLayouts, float4 faceZCoordLayouts)
        {
            // Determine the primary axis of the normal
            float3 absn = abs(coords);
            float3 absdir = absn > float3(max(absn.y,absn.z), max(absn.x,absn.z), max(absn.x,absn.y)) ? 1 : 0;
            // Convert the normal to a local face texture coord [-1,+1], note that tcAndLen.z==dot(coords,absdir)
            // and thus its sign tells us whether the normal is pointing positive or negative
            float3 tcAndLen = mul(absdir, float3x3(coords.zyx, coords.xzy, float3(-coords.xy,coords.z)));
            tcAndLen.xy /= tcAndLen.z;
            // Flip-flop faces for proper orientation and normalize to [-0.5,+0.5]
            bool2 positiveAndVCross = float2(tcAndLen.z, layout.x) > 0;
            tcAndLen.xy *= (positiveAndVCross[0] ? absdir.yx : (positiveAndVCross[1] ? float2(absdir[2],0) : float2(0,absdir[2]))) - 0.5;
            // Clamp values which are close to the face edges to avoid bleeding/seams (ie. enforce clamp texture wrap mode)
            tcAndLen.xy = clamp(tcAndLen.xy, edgeSize.xy, edgeSize.zw);
            // Scale and offset texture coord to match the proper square in the texture based on layout.
            float4 coordLayout = mul(float4(absdir,0), float4x4(faceXCoordLayouts, faceYCoordLayouts, faceZCoordLayouts, faceZCoordLayouts));
            tcAndLen.xy = (tcAndLen.xy + (positiveAndVCross[0] ? coordLayout.xy : coordLayout.zw)) * layout.yz;
            return tcAndLen.xy;
        }
#endif

        float3 RotateAroundYInDegrees (float3 vertex, float degrees)
        {
            float alpha = degrees * UNITY_PI / 180.0;
            float sina, cosa;
            sincos(alpha, sina, cosa);
            float2x2 m = float2x2(cosa, -sina, sina, cosa);
            return float3(mul(m, vertex.xz), vertex.y).xzy;
        }

        struct appdata_t {
            float4 vertex : POSITION;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f {
            float4 vertex : SV_POSITION;
            float3 texcoord : TEXCOORD0;
#ifdef _MAPPING_6_FRAMES_LAYOUT
            float3 layout : TEXCOORD1;
            float4 edgeSize : TEXCOORD2;
            float4 faceXCoordLayouts : TEXCOORD3;
            float4 faceYCoordLayouts : TEXCOORD4;
            float4 faceZCoordLayouts : TEXCOORD5;
#else
            float2 image180ScaleAndCutoff : TEXCOORD1;
            float4 layout3DScaleAndOffset : TEXCOORD2;
#endif
            UNITY_VERTEX_OUTPUT_STEREO
        };

        v2f vert (appdata_t v)
        {
            v2f o;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            float3 rotated = RotateAroundYInDegrees(v.vertex, _Rotation);
            o.vertex = UnityObjectToClipPos(rotated);
            o.texcoord = v.vertex.xyz;
#ifdef _MAPPING_6_FRAMES_LAYOUT
            // layout and edgeSize are solely based on texture dimensions and can thus be precalculated in the vertex shader.
            float sourceAspect = float(_MainTex_TexelSize.z) / float(_MainTex_TexelSize.w);
            // Use the halfway point between the 1:6 and 3:4 aspect ratios of the strip and cross layouts to
            // guess at the correct format.
            bool3 aspectTest =
                sourceAspect >
                float3(1.0, 1.0f / 6.0f + (3.0f / 4.0f - 1.0f / 6.0f) / 2.0f, 6.0f / 1.0f + (4.0f / 3.0f - 6.0f / 1.0f) / 2.0f);
            // For a given face layout, the coordinates of the 6 cube faces are fixed: build a compact representation of the
            // coordinates of the center of each face where the first float4 represents the coordinates of the X axis faces,
            // the second the Y, and the third the Z. The first two float componenents (xy) of each float4 represent the face
            // coordinates on the positive axis side of the cube, and the second (zw) the negative.
            // layout.x is a boolean flagging the vertical cross layout (for special handling of flip-flops later)
            // layout.yz contains the inverse of the layout dimensions (ie. the scale factor required to convert from
            // normalized face coords to full texture coordinates)
            if (aspectTest[0]) // horizontal
            {
                if (aspectTest[2])
                { // horizontal strip
                    o.faceXCoordLayouts = float4(0.5,0.5,1.5,0.5);
                    o.faceYCoordLayouts = float4(2.5,0.5,3.5,0.5);
                    o.faceZCoordLayouts = float4(4.5,0.5,5.5,0.5);
                    o.layout = float3(-1,1.0/6.0,1.0/1.0);
                }
                else
                { // horizontal cross
                    o.faceXCoordLayouts = float4(2.5,1.5,0.5,1.5);
                    o.faceYCoordLayouts = float4(1.5,2.5,1.5,0.5);
                    o.faceZCoordLayouts = float4(1.5,1.5,3.5,1.5);
                    o.layout = float3(-1,1.0/4.0,1.0/3.0);
                }
            }
            else
            {
                if (aspectTest[1])
                { // vertical cross
                    o.faceXCoordLayouts = float4(2.5,2.5,0.5,2.5);
                    o.faceYCoordLayouts = float4(1.5,3.5,1.5,1.5);
                    o.faceZCoordLayouts = float4(1.5,2.5,1.5,0.5);
                    o.layout = float3(1,1.0/3.0,1.0/4.0);
                }
                else
                { // vertical strip
                    o.faceXCoordLayouts = float4(0.5,5.5,0.5,4.5);
                    o.faceYCoordLayouts = float4(0.5,3.5,0.5,2.5);
                    o.faceZCoordLayouts = float4(0.5,1.5,0.5,0.5);
                    o.layout = float3(-1,1.0/1.0,1.0/6.0);
                }
            }
            // edgeSize specifies the minimum (xy) and maximum (zw) normalized face texture coordinates that will be used for
            // sampling in the texture. Setting these to the effective size of a half pixel horizontally and vertically
            // effectively enforces clamp mode texture wrapping for each individual face.
            o.edgeSize.xy = _MainTex_TexelSize.xy * 0.5 / o.layout.yz - 0.5;
            o.edgeSize.zw = -o.edgeSize.xy;
#else // !_MAPPING_6_FRAMES_LAYOUT
            // Calculate constant horizontal scale and cutoff for 180 (vs 360) image type
            if (_ImageType == 0)  // 360 degree
                o.image180ScaleAndCutoff = float2(1.0, 1.0);
            else  // 180 degree
                o.image180ScaleAndCutoff = float2(2.0, _MirrorOnBack ? 1.0 : 0.5);
            // Calculate constant scale and offset for 3D layouts
            if (_Layout == 0) // No 3D layout
                o.layout3DScaleAndOffset = float4(0,0,1,1);
            else if (_Layout == 1) // Left Right Side-by-Side 3D layout
                o.layout3DScaleAndOffset = float4(unity_StereoEyeIndex,0,0.5,1);
            else if (_Layout == 2) // Top Bottom Over-Under 3D layout
                o.layout3DScaleAndOffset = float4(0,1-unity_StereoEyeIndex,1,0.5);
            else if (_Layout == 3) // Right Left Side-by-Side 3D layout
                o.layout3DScaleAndOffset = float4(1-unity_StereoEyeIndex,0,0.5,1);
            else // Bottom Top Over-Under 3D layout
                o.layout3DScaleAndOffset = float4(0,unity_StereoEyeIndex,1,0.5);
#endif
            return o;
        }

        fixed4 frag (v2f i) : SV_Target
        {
            float2 tc = float2(0,0);
#ifdef _MAPPING_6_FRAMES_LAYOUT
            tc = ToCubeCoords(i.texcoord, i.layout, i.edgeSize, i.faceXCoordLayouts, i.faceYCoordLayouts, i.faceZCoordLayouts);
#endif
#ifdef _MAPPING_FISHEYE_LAYOUT
            tc = ToFisheyeCoords(i.texcoord);
            if (tc.x > i.image180ScaleAndCutoff[1])
                return half4(0,0,0,1);
            tc.x = fmod(tc.x*i.image180ScaleAndCutoff[0], 1);
            tc = (tc + i.layout3DScaleAndOffset.xy) * i.layout3DScaleAndOffset.zw;
#endif
#ifdef _MAPPING_LATITUDE_LONGITUDE_LAYOUT
            tc = ToRadialCoords(i.texcoord);
            if (tc.x > i.image180ScaleAndCutoff[1])
                return half4(0,0,0,1);
            tc.x = fmod(tc.x*i.image180ScaleAndCutoff[0], 1);
            tc = (tc + i.layout3DScaleAndOffset.xy) * i.layout3DScaleAndOffset.zw;
#endif

            //tc = TRANSFORM_TEX(tc, _MainTex);
            half4 tex = tex2D (_MainTex, tc);
            half3 c = DecodeHDR (tex, _MainTex_HDR);
            c = c * _Tint.rgb * unity_ColorSpaceDouble.rgb;
            c *= _Exposure;
#ifdef _DEBUG_DEBUG_ON
            return half4(tc, 0, 1);
#else
            return half4(c, 1);
#endif
        }
        ENDCG
    }
}


CustomEditor "SkyboxPanoramicShaderGmanGUI"
Fallback Off

}
