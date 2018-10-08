#ifndef ShaderTypes1_h
#define ShaderTypes1_h
#include <simd/simd.h>

#ifdef __METAL_VERSION__
using namespace metal;
#else
/// 96-bit 3 component float vector type
typedef struct __attribute__ ((packed)) packed_float3 {
    float x;
    float y;
    float z;
} packed_float3;
#endif

// We won't be calculating the light vector i.e.
// the vector from a point on the surface to the light source.
struct Light_t {
    packed_float3 direction;        // assume this is view space.
    packed_float3 ambientColor;
    packed_float3 diffuseColor;
    packed_float3 specularColor;
};


struct Uniforms_t
{
    simd::float4x4 modelViewMatrix;
    simd::float4x4 modelViewProjectionMatrix;
    simd::float3x3 normalMatrix;
    Light_t light;
};


#endif /* ShaderTypes1_h */
