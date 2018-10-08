// Blinn-Phong shading

#include <metal_stdlib>
#include "BlinnSharedTypes.h"

constant float3 kSpecularColor= { 1, 1, 1 };
constant float kSpecularPower = 80;


// [[attribute(n)]] is used in conjunction with [[stage_in]] in vertex function.
struct Vertex
{
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct ProjectedVertex
{
    float4 position [[position]];   // in clip space
    float3 viewVector;              // in view space
    float3 normal;                  // in view space
    float3 cubeTexCoords;           // use to texture a face of the cube.
    float2 texCoords;               // unused
};

vertex ProjectedVertex
vertexFunction(Vertex vert [[stage_in]],
               constant Uniforms_t &uniforms [[buffer(1)]])
{
    ProjectedVertex outVert;
    // Compute position of vertex in clip space
    outVert.position = uniforms.modelViewProjectionMatrix * vert.position;
    // compute the vector from the vertex to camera (or eye) in view space.
    // In view space, the eye's position is the origin.
    outVert.viewVector = float3(0)-(uniforms.modelViewMatrix * vert.position).xyz;
    outVert.normal = uniforms.normalMatrix * vert.normal;
    outVert.cubeTexCoords = vert.position.xyz;
    outVert.texCoords = vert.texCoords;
    return outVert;
}

// Apply Blinn-Phong shading
fragment float4
fragmentFunction(ProjectedVertex vert [[stage_in]],
                 constant Uniforms_t &uniforms      [[buffer(1)]],
                 texturecube<float>  cubeTexture    [[texture(0)]],
                 sampler             cubeSampler    [[sampler(0)]])
{
    Light_t light = uniforms.light;
    float3 diffuseColor = cubeTexture.sample(cubeSampler, vert.cubeTexCoords).rgb;

    // Calculate the various terms: ambient, diffuse & specular.
    float3 ambientTerm = light.ambientColor * diffuseColor;
    
    float3 normal = normalize(vert.normal);
    float diffuseIntensity = saturate(dot(normal, light.direction));
    float3 diffuseTerm = light.diffuseColor * diffuseColor * diffuseIntensity;
    
    float3 specularTerm(0);
    if (diffuseIntensity > 0)
    {
        // Calculate the direction towards to viewer's eye.
        float3 viewDirection = normalize(vert.viewVector);
        // Calculate the halfway vector between the light vector & the view direction.
        // The light direction should be normalized beforehand and is
        // the unit vector from the surface to the light source.
        float3 halfway = normalize(light.direction + viewDirection);
        // Compute the Blinn specular term.
        float specularFactor = pow(saturate(dot(normal, halfway)), kSpecularPower);
        specularTerm = light.specularColor * kSpecularColor * specularFactor;
    }

    return float4(ambientTerm + diffuseTerm + specularTerm, 1);
}
