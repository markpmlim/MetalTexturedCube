//
//  ViewController.m
//  CubeTextures2
//
//  Created by Mark Lim Pak Mun on 21/08/2018.
//  Copyright © 2018 Incremental Innovation. All rights reserved.
//

#import "Renderer.h"
#import <simd/simd.h>
#import "AAPLTransforms.h"
#import "BlinnSharedTypes.h"

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
    id<MTLSamplerState> _samplerState;
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
    float _rotation;
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
            //[self buildDepthTexture];
            _depthStencilState = [self buildDepthStencilState];
            _samplerState = [self buildSamplerState];
            NSArray *names = @[@"flowers_posx", @"flowers_negx", @"flowers_posy", @"flowers_negy", @"flowers_posz", @"flowers_negz"];
            _cubeTexture = [self textureCubeWithImagesNamed:names];
            _inFlightSemaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
            for (int i = 0; i < kInFlightCommandBuffers; i++) {
                _dynamicUniformsBuffer[i] = [_device newBufferWithLength:kAlignedUniformsSize
                                                                 options:MTLResourceStorageModeShared];
            }
            _inFlightIndex = 0;
            _light.direction = packed_float3{0.0, 0.0, -1.0};
            _light.ambientColor = packed_float3{0.1, 0.1, 0.1};
            _light.diffuseColor = packed_float3{1, 1, 1};
            _light.specularColor = packed_float3{0.2, 0.2, 0.2};
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

    vertexDescriptor.layouts[0] = [[MDLVertexBufferLayout alloc] initWithStride:sizeof(float) * 8 ];
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

- (id<MTLSamplerState>) buildSamplerState {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;
    id<MTLSamplerState> sampler = [_device newSamplerStateWithDescriptor:samplerDescriptor];
    return sampler;
}

// Assumes the image does not need to be flipped.
- (uint8_t *) dataForImage:(NSImage *)image
{
    NSRect proposedRect = NSMakeRect(0, 0,
                                     image.size.width, image.size.height);
    CGImageRef imageRef = [image CGImageForProposedRect:&proposedRect
                                                context:nil
                                                  hints:nil];
    // Create a suitable bitmap context for extracting the bits of the image
    const NSUInteger width = CGImageGetWidth(imageRef);
    const NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint8_t *rawData = (uint8_t *)calloc(height * width * 4, sizeof(uint8_t));
    const NSUInteger bytesPerPixel = 4;
    const NSUInteger bytesPerRow = bytesPerPixel * width;
    const NSUInteger bitsPerComponent = 8;
    // Will the function CGBitmapContextCreate add an alpha component?
    CGContextRef context = CGBitmapContextCreate(rawData,
                                                 width, height,
                                                 bitsPerComponent,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(context, CGRectMake(0, 0,
                                           width, height),
                       imageRef);
    CGContextRelease(context);

    return rawData;
}

- (id<MTLTexture>) textureCubeWithImagesNamed:(NSArray *)imageNames {
    NSImage *firstImage = [NSImage imageNamed:[imageNames lastObject]];
    const CGFloat cubeSize = firstImage.size.width;
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
        NSString *imageName = imageNames[slice];
        NSImage *image = [NSImage imageNamed:imageName];
        uint8_t *imageData = [self dataForImage:image];

        NSAssert(image.size.width == cubeSize && image.size.height == cubeSize,
                 @"Cube map images must be square and uniformly-sized");
        
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
    float4x4 modelMatrix = AAPL::rotate(_rotation, 1.0f, 1.0f, 1.0f);
    float4x4 modelViewMatrix = _viewMatrix * modelMatrix;
    
    frameState->modelViewMatrix = modelViewMatrix;
    frameState->modelViewProjectionMatrix = _projectionMatrix * modelViewMatrix;
    float3x3 normalMatrix = {
        modelViewMatrix.columns[0].xyz,
        modelViewMatrix.columns[1].xyz,
        modelViewMatrix.columns[2].xyz
    };
    frameState->normalMatrix = normalMatrix;
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
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
         {
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
            [renderEncoder setFragmentTexture:_cubeTexture
                                       atIndex:0];
            [renderEncoder setFragmentBuffer:_dynamicUniformsBuffer[_inFlightIndex]
                                      offset:0
                                     atIndex:1];
            [renderEncoder setFragmentSamplerState:_samplerState
                                           atIndex:0];
            [renderEncoder setVertexBuffer:_dynamicUniformsBuffer[_inFlightIndex]
                                    offset:0
                                   atIndex:1];
            // the cube's mesh has 1 instance of MTKMeshBuffer and 1 instance of MTKSubmesh
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
