//
//  OpenGLRenderer.swift
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.
//

import AppKit
import ModelIO
import OpenGL.GL3
import GLKit
import simd

class OpenGLRenderer: NSObject
{
    var defaultFBOName: GLuint = 0
    let UNIFORMS_BLOCK_BINDING0: GLuint = 0
    var glslProgram: GLuint = 0

    var nodes = [Node]()
    var uboBlocks = [GLuint]()      // KIV

    var viewSize: CGSize!
    var projectionMatrix = GLKMatrix4Identity
    var viewMatrix = GLKMatrix4Identity
    var elapsedTime: Double = 0.0
    var camera: VirtualCamera!

    init(_ defaultFBOName: GLuint, viewSize: CGSize)
    {
        super.init()

        self.defaultFBOName = defaultFBOName
        self.camera = VirtualCamera(screenSize: viewSize)
        guard let vertexSourceURL = Bundle.main.url(forResource: "PBR",
                                                    withExtension: "vert")
        else {
            fatalError("Vertex Shader")
        }
        
        guard let fragmentSourceURL = Bundle.main.url(forResource: "PBR",
                                                      withExtension: "frag")
        else {
            fatalError("Fragment Shader")
        }

        glslProgram = buildProgram(with: vertexSourceURL,
                                   and: fragmentSourceURL)

        let allocator = MDLMeshBufferDataAllocator()

        let urls = [
            "gold/sphere",
            "grass/sphere",
            "plastic/sphere",
            "rusted_iron/sphere",
            "wall/sphere",
        ]
        let positions = [
            GLKVector3Make(-6.0, 0.0, -5.0),
            GLKVector3Make(-3.0, 0.0, -5.0),
            GLKVector3Make( 0.0, 0.0, -5.0),
            GLKVector3Make( 3.0, 0.0, -5.0),
            GLKVector3Make( 6.0, 0.0, -5.0),
        ]
 
        for i in 0..<urls.count {
            guard let assetURL = Bundle.main.url(forResource: urls[i],
                                                 withExtension: "obj")
            else {
                fatalError()
            }

           let mdlAsset = MDLAsset(url: assetURL,
                                    vertexDescriptor: nil,
                                    bufferAllocator: allocator)
            // We assume there is only 1 object and it is an instance of MDLMesh
            guard let sourceMesh = mdlAsset[0] as? MDLMesh
            else {
                fatalError("Did not find any meshes in the Model I/O asset")
            }

            if sourceMesh.isKind(of: MDLMesh.self) {
                sourceMesh.vertexDescriptor = buildVertexDescriptor(sourceMesh)
                let node = Node(mesh: sourceMesh,
                                with: sourceMesh.vertexDescriptor)
                node.position = positions[i]
                nodes.append(node)
            }
        } // for

        glEnable(GLenum(GL_DEPTH_TEST))
        glDepthFunc(GLenum(GL_LESS))
    }

    func buildVertexDescriptor(_ mdlMesh: MDLMesh) -> MDLVertexDescriptor
    {
        let vertexDescr = mdlMesh.vertexDescriptor
        var hasNormals = false
        var hasTexCoords = false
        // Check if the mesh has normals and texture coordinates
        // There is a better way for checking: vertexAttributeDataForAttributeNamed
        for i in 0..<vertexDescr.layouts.count {
            let vertAttribute = vertexDescr.attributes[i] as! MDLVertexAttribute
            let name = vertAttribute.name
            if name == MDLVertexAttributeNormal {
                hasNormals = true
            }
            if name == MDLVertexAttributeTextureCoordinate {
                hasTexCoords = true
            }
        }
        let vertexDescriptor = MDLVertexDescriptor()
        // Attributes
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                            format: .float3,
                                                            offset: 0,
                                                            bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                            format: .float3,
                                                            offset: MemoryLayout<Float>.stride * 3,
                                                            bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                            format: .float2,
                                                            offset: MemoryLayout<Float>.stride * 6,
                                                            bufferIndex: 0)
        vertexDescriptor.attributes[3] = MDLVertexAttribute(name: MDLVertexAttributeTangent,
                                                            format: .float4,
                                                            offset: MemoryLayout<Float>.stride * 8,
                                                            bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 12)

        if !hasNormals {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal,
                                  creaseThreshold: 0.1)
        }

        if !hasTexCoords {
            mdlMesh.addUnwrappedTextureCoordinates(forAttributeNamed: MDLVertexAttributeTextureCoordinate)
        }

/*
        // The call below will guarantee an orthogonal tangent basis
        // Only availabe in macOS 10.13 or later
        mdlMesh.addOrthTanBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                normalAttributeNamed: MDLVertexAttributeNormal,
                                tangentAttributeNamed: MDLVertexAttributeTangent)
 */
        // The method below will return tangents that are orthogonal to the normal.
        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                normalAttributeNamed: MDLVertexAttributeNormal,
                                tangentAttributeNamed: MDLVertexAttributeTangent)

        // Are the following instructions necessary?
        vertexDescriptor.setPackedOffsets()
        vertexDescriptor.setPackedStrides()

        return vertexDescriptor
    }

    func resize(_ size: CGSize)
    {
        viewSize = size
        glViewport(0, 0,
                   GLsizei(viewSize.width), GLsizei(viewSize.height))
        let aspect = Float(size.width/size.height)
        projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65),
                                                     aspect,
                                                     1.0, 100.0)
        camera.resize(with: size)
    }

    func updateCamera(_ framesPerSecond: Double)
    {
        camera.update(Float(1.0/framesPerSecond))
    }

    let lightPositions = [
        GLKVector3Make(-5.0,  5.0, 5.0),
        GLKVector3Make( 5.0,  5.0, 5.0),
        GLKVector3Make(-5.0, -5.0, 5.0),
        GLKVector3Make( 5.0, -5.0, 5.0),
    ]
    let lightColors = [
        GLKVector3Make(300.0, 300.0, 300.0),
        GLKVector3Make(300.0, 300.0, 300.0),
        GLKVector3Make(300.0, 300.0, 300.0),
        GLKVector3Make(300.0, 300.0, 300.0),
    ]

    func draw(_ framesPerSecond: Double)
    {
        elapsedTime += 1.0/framesPerSecond
        updateCamera(framesPerSecond)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT))
        glClearColor(0.5, 0.5, 0.5, 1.0)

        glUseProgram(glslProgram)
        let viewMatrixLoc = glGetUniformLocation(glslProgram, "uViewMatrix")
        let projectionMatrixLoc = glGetUniformLocation(glslProgram, "uProjectionMatrix")
        let normalMatrixLoc = glGetUniformLocation(glslProgram, "uNormalMatrix")

        let orientationMatrix = GLKMatrix4MakeWithQuaternion(camera.orientation)
        viewMatrix = GLKMatrix4Multiply(camera.viewMatrix, orientationMatrix)
        let cameraPos = GLKVector3Make(camera.viewMatrix.m30,
                                       camera.viewMatrix.m31,
                                       camera.viewMatrix.m32)
        let cameraPosLoc = glGetUniformLocation(glslProgram, "cameraPos")
        glUniform3fv(cameraPosLoc, 1, cameraPos.array)
        for i in 0..<lightPositions.count {
            let lightPos = "lightPositions[" + String(i) + "]"
            let lightPosLoc = glGetUniformLocation(glslProgram, lightPos)

            glUniform3fv(lightPosLoc, 1, lightPositions[i].array)

            let lightColor = "lightColors[" + String(i) + "]"
            let lightColorLoc = glGetUniformLocation(glslProgram, lightColor)
            glUniform3fv(lightColorLoc, 1, lightColors[i].array)
        }
 
        glUniformMatrix4fv(viewMatrixLoc,
                           1,
                           GLboolean(GL_FALSE),
                           viewMatrix.array)
       glUniformMatrix4fv(projectionMatrixLoc,
                           1,
                           GLboolean(GL_FALSE),
                           projectionMatrix.array)

        for node in nodes {
            let modelMatrix = node.worldTransform
            var isInvertible: Bool = false
            let normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelMatrix),
                                                                                 &isInvertible)
            // If there is no shearing or non-uniform scaling, the normal matrix is
            // the upperLeft3x3 sub-matrix of the modelMatrix.
            glUniformMatrix3fv(normalMatrixLoc,
                               1,
                               GLboolean(GL_FALSE),
                               normalMatrix.array)
            node.draw(elapsedTime: elapsedTime,
                      program: glslProgram)
        }

        glUseProgram(0)
    }

    /*
     Only expect a pair of vertex and fragment shaders.
     This function should work for modern OpenGL syntax.
     */
    func buildProgram(with vertSrcURL: URL,
                      and fragSrcURL: URL) -> GLuint
    {
        // Prepend the #version preprocessor directive to the vertex and fragment shaders.
        var  glLanguageVersion: Float = 0.0
        let glslVerstring = String(cString: glGetString(GLenum(GL_SHADING_LANGUAGE_VERSION)))
        let index = glslVerstring.index(glslVerstring.startIndex, offsetBy: 0)

        let range = index..<glslVerstring.endIndex
        //let verStr = glslVerstring.substring(with: range)
        let verStr = String(glslVerstring[range])

        let scanner = Scanner(string: verStr!)
        scanner.scanFloat(&glLanguageVersion)
        // We need to convert the float to an integer and then to a string.
        let shaderVerStr = String(format: "#version %d", Int(glLanguageVersion*100))

        var vertSourceString = String()
        var fragSourceString = String()
        do {
            vertSourceString = try String(contentsOf: vertSrcURL)
        }
        catch _ {
            Swift.print("Error loading vertex shader")
        }

        do {
            fragSourceString = try String(contentsOf: fragSrcURL)
        }
        catch _ {
            Swift.print("Error loading fragment shader")
        }
        vertSourceString = shaderVerStr + "\n" + vertSourceString
        fragSourceString = shaderVerStr + "\n" + fragSourceString

        // Create a GLSL program object.
        let prgName = glCreateProgram()

        // We can choose to bind our attribute variable names to specific
        //  numeric attribute locations. Must be done before linking.
        //glBindAttribLocation(prgName, AAPLVertexAttributePosition, "mcPosition")

        let vertexShader = glCreateShader(GLenum(GL_VERTEX_SHADER))
        var cSource = vertSourceString.cString(using: .utf8)!
        var glcSource: UnsafePointer<GLchar>? = UnsafePointer<GLchar>(cSource)
        glShaderSource(vertexShader, 1, &glcSource, nil)
        glCompileShader(vertexShader)

        var compileStatus : GLint = 0
        glGetShaderiv(vertexShader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if compileStatus == GL_FALSE {
            var infoLength : GLsizei = 0
            glGetShaderiv(vertexShader, GLenum(GL_INFO_LOG_LENGTH), &infoLength)
            if infoLength > 0 {
                // Convert an UnsafeMutableRawPointer to UnsafeMutablePointer<GLchar>
                let log = malloc(Int(infoLength)).assumingMemoryBound(to: GLchar.self)
                glGetShaderInfoLog(vertexShader, infoLength, &infoLength, log)
                let errMsg = NSString(bytes: log,
                                      length: Int(infoLength),
                                      encoding: String.Encoding.ascii.rawValue)
                print(errMsg!)
                glDeleteShader(vertexShader)
                free(log)
            }
        }
        // Attach the vertex shader to the program.
        glAttachShader(prgName, vertexShader);

        // Delete the vertex shader because it's now attached to the program,
        //  which retains a reference to it.
        glDeleteShader(vertexShader);

        /*
         * Specify and compile a fragment shader.
         */
        let fragmentShader = glCreateShader(GLenum(GL_FRAGMENT_SHADER))
        cSource = fragSourceString.cString(using: .utf8)!
        glcSource = UnsafePointer<GLchar>(cSource)
        glShaderSource(fragmentShader, 1, &glcSource, nil)
        glCompileShader(fragmentShader)
        
        glGetShaderiv(fragmentShader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if compileStatus == GL_FALSE {
            var infoLength : GLsizei = 0
            glGetShaderiv(fragmentShader, GLenum(GL_INFO_LOG_LENGTH), &infoLength)
            if infoLength > 0 {
                // Convert an UnsafeMutableRawPointer to UnsafeMutablePointer<GLchar>
                let log = malloc(Int(infoLength)).assumingMemoryBound(to: GLchar.self)
                glGetShaderInfoLog(fragmentShader, infoLength, &infoLength, log)
                let errMsg = NSString(bytes: log,
                                      length: Int(infoLength),
                                      encoding: String.Encoding.ascii.rawValue)
                print(errMsg!)
                glDeleteShader(fragmentShader)
                free(log)
            }
        }

        // Attach the fragment shader to the program.
        glAttachShader(prgName, fragmentShader)

        // Delete the fragment shader because it's now attached to the program,
        //  which retains a reference to it.
        glDeleteShader(fragmentShader)

        /*
         * Link the program.
         */
        var linkStatus: GLint = 0
        glLinkProgram(prgName)
        glGetProgramiv(prgName, GLenum(GL_LINK_STATUS), &linkStatus)

        if (linkStatus == GL_FALSE) {
            var logLength : GLsizei = 0
            glGetProgramiv(prgName, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if (logLength > 0) {
                let log = malloc(Int(logLength)).assumingMemoryBound(to: GLchar.self)
                glGetProgramInfoLog(prgName, logLength, &logLength, log)
                NSLog("Program link log:\n%s.\n", log)
                free(log)
            }
        }

        return prgName
    }
}

extension vector_float3
{
    func toArray() -> [Float] {
        return [Float](arrayLiteral:
            self.x, self.y, self.z)
    }
}

// tuples to an array
extension GLKMatrix4 {
    var array: [Float] {
        return (0..<16).map { i in
            self[i]
        }
    }
}

extension GLKMatrix3 {
    var array: [Float] {
        return (0..<9).map { i in
            self[i]
        }
    }
}

// tuples to an array
extension GLKVector3 {
    var array: [Float] {
        return (0..<3).map { i in
            self[i]
        }
    }
}
