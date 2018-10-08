//
//  ViewController.h
//  CubeTextures2
//
//  Created by Mark Lim Pak Mun on 21/08/2018.
//  Copyright © 2018 Mark Lim Pak Mun. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface Renderer : NSObject <MTKViewDelegate>

- (instancetype) initWithMetalView:(MTKView *)mtkView;

@end

