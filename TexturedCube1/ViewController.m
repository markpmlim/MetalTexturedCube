//
//  ViewController.m
//  CubeTextures2
//
//  Created by Mark Lim Pak Mun on 21/08/2018.
//  Copyright © 2018 Incremental Innovation. All rights reserved.
//

@import MetalKit;
#import "ViewController.h"
#import "Renderer.h"

@interface ViewController() {
    MTKView *_view;
    Renderer *_renderer;
}
@end

@implementation ViewController


- (void) viewDidLoad {
    [super viewDidLoad];
    _view = (MTKView *)self.view;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _view.sampleCount = 4;
    
    _renderer = [[Renderer alloc] initWithMetalView:_view];
    _view.delegate = _renderer;

    //Need to setup the initial matrices
    [_renderer mtkView:_view
drawableSizeWillChange:_view.drawableSize];
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end
