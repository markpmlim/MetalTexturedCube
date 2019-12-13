This project consists of 3 demos. All 3 demos illustrates how to texture each of the 6 faces of a cube with a different texture. The texture coordinates of each face are not used. The position of the cube's vertex is used instead.


TexturedCube1 Demo

The cube map texture to be used for the 6 faces of the cube is instantiated from 6 graphic files. The fragment function of the metal shader is an implementation of Blinn-Phong lighting. The metal shader is modified from that used in the up-and-running demo. 


TexturedCube2 Demo

The cube map texture is instantiated procedurally. Each face of the cube will be textured with a different colour. The fragment function is an implementation of Phong lighting. The metal shader is modified from that used in www.Raywenderlich.com's Metal demo.


TexturedCube3 Demo

The cube map texture to be used for the 6 faces of the cube is instantiated from 6 graphic files (like demo1). Both demo2 and demo3 shares the same metal shader.


TexuredCube.playground Demo

This is a Swift-SceneKit playground. It shows how to pass values between SCNShadable Entry points. The "#pragma varyings" directive is only available in XCode 9.x or later.


References:

https://sites.google.com/site/john87connor/texture-object/tutorial-09-5-cube-map

http://metalbyexample.com/up-and-running-3

https://www.raywenderlich.com/976-ios-metal-tutorial-with-swift-part-5-switching-to-metalkit
