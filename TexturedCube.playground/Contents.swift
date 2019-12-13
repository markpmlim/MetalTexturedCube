/*
 Swift playgrounds can be used to test shader modifiers quickly.
 This playground demonstrates how to use a pair of shader modifiers
 to texture the 6 faces of a cube in a SceneKit environment.
 
 The 6 textures are instantiated from  a vertical strip of 6 images.
 Requirements: XCode 9.x or later, macOS 10.13 or later.
 
 Reference: https://stackoverflow.com/questions/37546352/passing-values-between-scnshadable-entry-points
 
 */

import Cocoa
import SceneKit
import PlaygroundSupport
import MetalKit

let cubeGeometry = SCNBox(width: 1.0, height: 1.0, length: 1.0,
                          chamferRadius: 0.0)

let cubeNode = SCNNode(geometry: cubeGeometry)

let device = MTLCreateSystemDefaultDevice()!
let textureLoader = MTKTextureLoader(device: device)
// The option below requires macOS 10.12.x or later
let options: [MTKTextureLoader.Option : Any] = [MTKTextureLoader.Option.cubeLayout : MTKTextureLoader.CubeLayout.vertical]
var texture: MTLTexture!

do {
    let textureURL = Bundle.main.url(forResource: "VerticalStrip",
                                     withExtension: "jpg")!
    texture = try textureLoader.newTexture(URL: textureURL,
                                           options: options)
}
catch {
    fatalError("Could not load cube map from resources folder: \(error)")
}

var materialProperty = SCNMaterialProperty(contents: texture!)

// The directive "#pragma varyings" is only available in MSL.
// The pragma might not be available in earlier versions of macOS.
let geometryModifier =
    "#pragma varyings\n" +
    "float3 cubemapCoord;\n\n" +
    "#pragma body\n" +
    "out.cubemapCoord = _geometry.position.xyz;\n"

let surfaceModifier =
    "#pragma arguments\n" +
    "texturecube<float> texture;\n\n" +
    "#pragma body\n" +
    "constexpr sampler s(filter::linear, mip_filter::linear);\n" +
    "_surface.diffuse = texture.sample(s, in.cubemapCoord);\n"

cubeGeometry.setValue(materialProperty, forKey: "texture")
cubeGeometry.shaderModifiers = [
    .geometry : geometryModifier,
    .surface : surfaceModifier,
]

// Do a simple animation
let angle = CGFloat.pi/6
cubeNode.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: angle, y: angle, z: angle,
                                                             duration: 0.5)))
let frameRect = NSRect(x: 0, y: 0,
                       width: 480, height: 270)
let sceneView = SCNView(frame: frameRect)
let scene = SCNScene()

sceneView.scene = scene
scene.rootNode.addChildNode(cubeNode)
sceneView.backgroundColor = NSColor.gray
sceneView.autoenablesDefaultLighting = true
sceneView.allowsCameraControl = true
sceneView.showsStatistics = true

PlaygroundPage.current.liveView = sceneView
