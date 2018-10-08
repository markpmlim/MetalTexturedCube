#ifndef ShaderTypes2_h
#define ShaderTypes2_h
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
// This vector is the reverse of the incident ray on the surface.
struct Light_t {
    packed_float3 direction;    // normalized and in view space
    packed_float3 color;
    float ambientIntensity;
    float diffuseIntensity;
    float shininess;
    float specularIntensity;
};


struct Uniforms_t
{
    simd::float4x4 modelViewMatrix;
    simd::float4x4 projectionMatrix;
    Light_t light;
};


#endif /* ShaderTypes_h */
