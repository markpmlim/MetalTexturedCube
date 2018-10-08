//
//  ViewController.m
//  CubeTextures2
//
//  Created by Mark Lim Pak Mun on 21/08/2018.
//  Copyright © 2018 Incremental Innovation. All rights reserved.
//

#import <simd/simd.h>
#import "Renderer.h"
#import "AAPLTransforms.h"
#import "PhongSharedTypes.h"

using namespace simd;

static const long   kInFlightCommandBuffers = 3;
static const float  kFOVY   = 65.0f;
static const float3 kEye    = {0.0f, 0.0f, 3.0f};
static const float3 kCenter = {0.0f, 0.0f, 1.0f};
static const float3 kUp     = {0.0f, 1.0f, 0.0f};

static const size_t kAlignedUniformsSize = (sizeof(Uniforms_t) & ~0xFF) + 0x100;

@interface Renderer () {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _renderPipeline;
    id<MTLDepthStencilState> _depthStencilState;
    MDLVertexDescriptor *_mdlVertexDescriptor;
    MTKMesh *_cubeMesh;
    __weak MTKView *_view;
    id<MTLTexture> _depthTexture;
    id<MTLSamplerState> _cubeSamplerState;
    id<MTLTexture> _cubeTexture;
}
@end

@implementation Renderer {
    // constant synchronization for buffering <kInFlightCommandBuffers> frames
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLBuffer> _dynamicUniformsBuffer[kInFlightCommandBuffers];
    NSUInteger _inFlightIndex;
    float4x4 _projectionMatrix;
    float4x4 _viewMatrix;
    float _rotation;                // angle of rotation
    Light_t _light;
}

- (instancetype) initWithMetalView:(MTKView *)mtkView {
    self = [super init];
    if (self != nil) {
        _device = MTLCreateSystemDefaultDevice();
        mtkView.device = _device;
        _view = mtkView;
        _commandQueue = [_device newCommandQueue];

        _mdlVertexDescriptor = [self buildVertexDescriptor];
        _renderPipeline = [self buildPipeline:_device
                                         view:mtkView
                             vertexDescriptor:_mdlVertexDescriptor];
        if (_renderPipeline != nil) {
            [self buildResources];
            _depthStencilState = [self buildDepthStencilState];
            [self buildSamplerStates];
            _cubeTexture = [self textureCube];
            _inFlightSemaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
            for (int i = 0; i < kInFlightCommandBuffers; i++) {
                _dynamicUniformsBuffer[i] = [_device newBufferWithLength:kAlignedUniformsSize
                                                                 options:MTLResourceStorageModeShared];
            }
            _inFlightIndex = 0;
            // The source of light
            _light.direction = packed_float3{0.0, 0.0, -1.0};
            _light.color = packed_float3{1.0, 1.0, 1.0};
            _light.ambientIntensity = 0.1;
            _light.diffuseIntensity = 0.8;
            _light.shininess = 10;
            _light.specularIntensity = 2;
       }
        else {
            self = nil;
        }
    }
    return self;
}

- (MDLVertexDescriptor *) buildVertexDescriptor {
    MDLVertexDescriptor *vertexDescriptor = [[MDLVertexDescriptor alloc] init];
    vertexDescriptor.attributes[0] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributePosition
                                                                       format:MDLVertexFormatFloat3
                                                                       offset:0
                                                                  bufferIndex:0];
    vertexDescriptor.attributes[1] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeNormal
                                                                       format:MDLVertexFormatFloat3
                                                                       offset:3 * sizeof(float)
                                                                  bufferIndex:0];
    vertexDescriptor.attributes[2] = [[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeTextureCoordinate
                                                                       format:MDLVertexFormatFloat2
                                                                       offset:6 * sizeof(float)
                                                                  bufferIndex:0];

    vertexDescriptor.layouts[0] = [[MDLVertexBufferLayout alloc] initWithStride:sizeof(float) * 8];
    return vertexDescriptor;
}

- (id<MTLRenderPipelineState>) buildPipeline:(id<MTLDevice>)device
                                        view:(MTKView *)mtkView
                            vertexDescriptor:(MDLVertexDescriptor *)mdlVertexDescriptor {
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertexFunction"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentFunction"];
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;

    pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
    pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
    pipelineDescriptor.sampleCount = mtkView.sampleCount;
    MTLVertexDescriptor *mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlVertexDescriptor);
    pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor;
    NSError *err = nil;
    id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                                      error:&err];
    if (err != nil) {
        NSLog(@"%@", err);
        return nil;
    }
    else {
        return pipelineState;
    }
}

- (void) buildResources {
    MTKMeshBufferAllocator *bufferAllocator = [[MTKMeshBufferAllocator alloc] initWithDevice: _device];
    MDLMesh *boxMesh = [MDLMesh newBoxWithDimensions:(vector_float3){1.0, 1.0, 1.0}
                                         segments:(vector_uint3){1, 1, 1}
                                     geometryType:MDLGeometryTypeTriangles
                                    inwardNormals:NO
                                        allocator:bufferAllocator];
    boxMesh.vertexDescriptor = _mdlVertexDescriptor;
    NSError *error = nil;
    _cubeMesh = [[MTKMesh alloc] initWithMesh:boxMesh
                                       device:_device
                                        error:&error];
}


- (id<MTLDepthStencilState>) buildDepthStencilState {
    MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
    depthDescriptor.depthWriteEnabled = YES;
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    id<MTLDepthStencilState> depthStencil = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
    return depthStencil;
}

- (void) buildSamplerStates {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;
    id<MTLSamplerState> sampler = [_device newSamplerStateWithDescriptor:samplerDescriptor];
    _cubeSamplerState = sampler;

}

// Returns the raw bitmap data of 1 slice
// Caller should free the allocated memory.
- (u_int8_t *) dataForSlice:(u_int8_t)slice
                      width:(u_int16_t)width
                     height:(u_int16_t)height
{
    NSAssert(width == height,
             @"Cube map images must be square and uniformly-sized");
    const NSUInteger bytesPerPixel = 4;
    const NSUInteger bytesPerRow = bytesPerPixel * width;
    uint8_t pixels[6][4] = {
        {255, 0, 0, 255},   // red
        {0, 255, 0, 255},   // green
        {0, 0, 255, 255},   // blue
        {255, 255, 0, 255}, // yellow
        {255, 0, 255, 255}, // magneta
        {0, 255, 255, 255}, // cyan
    };
    uint8_t *rawData = (uint8_t *)calloc(height * width * 4, sizeof(uint8_t));
    for (int row=0; row<height; row++) {
        for (int col=0; col<height; col++) {
            NSUInteger loc = (row*bytesPerRow) + bytesPerPixel * col;
            //int loc = (row*width + col) * bytesPerPixel;
            rawData[loc+0] = pixels[slice][0];
            rawData[loc+1] = pixels[slice][1];
            rawData[loc+2] = pixels[slice][2];
            rawData[loc+3] = pixels[slice][3];
            //printf("%ld ", loc);
        }
        //printf("\n");
    }
    return rawData;
}

// Returns a cube map texture
- (id<MTLTexture>) textureCube {
    const CGFloat cubeSize = 256.0;
    const NSUInteger bytesPerPixel = 4;
    const NSUInteger bytesPerRow = bytesPerPixel * cubeSize;
    const NSUInteger bytesPerImage = bytesPerRow * cubeSize;

    MTLRegion region = MTLRegionMake2D(0, 0,
                                       cubeSize, cubeSize);

     MTLTextureDescriptor *cubeMapDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                              size:cubeSize
                                                                                         mipmapped:NO];
    cubeMapDesc.storageMode = MTLStorageModeManaged;
    cubeMapDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> cubeTexture = [_device newTextureWithDescriptor:cubeMapDesc];
    for (size_t slice = 0; slice < 6; ++slice) {
        uint8_t *imageData = [self dataForSlice:slice
                                          width:cubeSize
                                         height:cubeSize];

        [cubeTexture replaceRegion:region               // dest
                       mipmapLevel:0
                             slice:slice
                         withBytes:imageData            // src
                       bytesPerRow:bytesPerRow
                     bytesPerImage:bytesPerImage];
        free(imageData);
    }
    return cubeTexture;
}

#pragma MTKViewDelegate methods
// This should be called immediately after the instantiation of the Renderer object.
- (void) mtkView:(MTKView *)mtkView
drawableSizeWillChange:(CGSize)size {
    // when reshape is called, update the view and projection matricies since this means the view orientation or size changed
    float aspect = fabs(mtkView.bounds.size.width / mtkView.bounds.size.height);
    _projectionMatrix = AAPL::perspective_fov(kFOVY,
                                              aspect,
                                              0.1f, 10.0f);
    _viewMatrix = AAPL::lookAt(kEye, kCenter, kUp);
}

- (void) updateUniformsBuffer {
    _rotation += 0.5;
    Uniforms_t *frameState = (Uniforms_t *)[_dynamicUniformsBuffer[_inFlightIndex] contents];
    //float4x4 modelMatrix = matrix_identity_float4x4;
    float4x4 modelMatrix = AAPL::rotate(_rotation,
                                        1.0f, 1.0f, 1.0f);  // axis of rotation
    float4x4 modelViewMatrix = _viewMatrix * modelMatrix;

    frameState->modelViewMatrix = modelViewMatrix;
    frameState->projectionMatrix = _projectionMatrix;
    frameState->light = _light;
}

- (void) drawInMTKView:(MTKView *)mtkView {
    @autoreleasepool {
        // Wait to ensure only kInFlightCommandBuffers are getting proccessed by
        //  any stage in the Metal pipeline (App, Metal, Drivers, GPU, etc)
        dispatch_semaphore_wait(_inFlightSemaphore,
                                DISPATCH_TIME_FOREVER);
        [self updateUniformsBuffer];

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
            // GPU has completed rendering the frame and is done using the contents
            //  of any buffers previously encoded on the CPU for that frame.
            // Signal the semaphore and allow the CPU to proceed and construct the next frame.
            dispatch_semaphore_signal(block_sema);
        }];

        MTLRenderPassDescriptor *renderPassDescriptor = mtkView.currentRenderPassDescriptor;
        if (renderPassDescriptor != nil) {
            id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            [renderEncoder setRenderPipelineState:_renderPipeline];
            [renderEncoder setDepthStencilState:_depthStencilState];

            [renderEncoder setFragmentBuffer:_dynamicUniformsBuffer[_inFlightIndex]
                                      offset:0
                                     atIndex:1];
            [renderEncoder setFragmentTexture:_cubeTexture
                                      atIndex:0];
            [renderEncoder setFragmentSamplerState:_cubeSamplerState
                                           atIndex:0];

            [renderEncoder setVertexBuffer:_dynamicUniformsBuffer[_inFlightIndex]
                                    offset:0
                                   atIndex:1];
            // The cube's mesh has 1 instance of MTKMeshBuffer and 1 instance of MTKSubmesh
            [renderEncoder setVertexBuffer:_cubeMesh.vertexBuffers[0].buffer
                                    offset:0
                                   atIndex:0];
            MTKSubmesh *subMesh = _cubeMesh.submeshes[0];
            [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                      indexCount:subMesh.indexCount
                                       indexType:subMesh.indexType
                                     indexBuffer:subMesh.indexBuffer.buffer
                               indexBufferOffset:subMesh.indexBuffer.offset];
            [renderEncoder endEncoding];
            if (mtkView.currentDrawable != nil)
                [commandBuffer presentDrawable:mtkView.currentDrawable];

             [commandBuffer commit];
        }
        _inFlightIndex = (_inFlightIndex + 1) % kInFlightCommandBuffers;
    }
}
@end
