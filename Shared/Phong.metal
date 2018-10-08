#include <metal_stdlib>
//#include <metal_common>
#include <simd/simd.h>
#include "PhongSharedTypes.h"


// The layout corresponds to the one returned by ModelIO methods.
struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};


struct VertexOut {
    float4 position [[position]];                   // clip space
    float3 cubeTexCoords [[user(texturecoord)]];
    float3 viewVector;                              // view space
    float3 normal [[user(normal)]];                 // view space
    float2 texCoords [[user(texCoords)]];           // not used.
};

vertex VertexOut
vertexFunction(         VertexIn in             [[stage_in]],
               constant Uniforms_t &uniforms    [[buffer(1)]]) {

    VertexOut out;
    float4x4 mv_Matrix = uniforms.modelViewMatrix;
    float4x4 proj_Matrix = uniforms.projectionMatrix;

    out.position = proj_Matrix * mv_Matrix * float4(in.position, 1.0);
    out.cubeTexCoords = in.position;
    out.normal = (mv_Matrix * float4(in.normal, 0.0)).xyz;
    out.texCoords = in.texCoords;
    // Compute the view vector from surface towards eye/camera.
    out.viewVector = float3(0)-(mv_Matrix * float4(in.position, 1.0)).xyz;
    return out;
}

// Apply Phong shading
fragment float4
fragmentFunction(VertexOut fragmentIn            [[ stage_in ]],
                 constant Uniforms_t &uniforms   [[buffer(1)]],
                 texturecube<float>  cubeTexture [[texture(0)]],
                 sampler             cubeSampler [[sampler(0)]]) {

    Light_t light = uniforms.light;
    // Ambient contribution
    float4 ambientColor = float4(light.color * light.ambientIntensity, 1.0);
    // Diffuse contribution
    float diffuseFactor = max(0.0,
                              dot(fragmentIn.normal,
                                  light.direction)); // 1
    float4 diffuseColor = float4(light.color * light.diffuseIntensity * diffuseFactor, 1.0); // 2

    float2 uv = fragmentIn.texCoords;   // unused
    float3 normal = fragmentIn.normal;
    // Specular contribution
    // viewDirection.
    float3 viewDirection = normalize(fragmentIn.viewVector);

    // The direction of the light vector is from the surface to the  light source.
    // It's already normalized. But the function "reflect" needs the incident ray.
    float3 reflectedRay = reflect(-light.direction,
                                  normal);
    float specularFactor = pow(max(0.0, dot(reflectedRay, viewDirection)),
                               light.shininess);
    float4 specularColor = float4(light.color * light.specularIntensity * specularFactor , 1.0);

    float3 cubeTexCoords = fragmentIn.cubeTexCoords;
    float4 color = cubeTexture.sample(cubeSampler, cubeTexCoords);
    return color * (ambientColor + diffuseColor + specularColor);
}


