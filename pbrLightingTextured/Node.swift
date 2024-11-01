//
//  Node.swift
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa
import ModelIO
import GLKit
import simd


class Node
{
    var position = GLKVector3Make(0.0, 0.0, 0.0)
    var scaleFactor: Float = 1.0
    var rotation =  GLKVector3Make(0, 1.0, 0)       // about y-axis
    var angle: Float = 0

    var worldTransform: GLKMatrix4 {
        var modelMatrix = GLKMatrix4TranslateWithVector3(GLKMatrix4Identity,
                                                         position)
        let rotateMatrix = GLKMatrix4MakeRotation(angle,
                                                  rotation.x, rotation.y, rotation.z)
        let scaleMatrix = GLKMatrix4MakeScale(scaleFactor, scaleFactor, scaleFactor)
        modelMatrix = GLKMatrix4Multiply(modelMatrix, scaleMatrix)
        return GLKMatrix4Multiply(modelMatrix, rotateMatrix)
    }

    weak var parent: Node?
    var children = [Node]()

    let mdlMesh: MDLMesh
    var textures = [Textures]()
    var materialConstants = [MaterialConstants]()
    var hasTextures = [UseTextures]()
    var uboBlocks = [GLuint]()

    var vertexArrayObject: GLuint = 0
    var vertexBufferObject: GLuint = 0
    var indexBufferObjects = [GLuint]()     // # of submeshes
    var indexCount = [GLsizei]()
    var indexType = [GLenum]()
    var indexDataSize = [GLsizeiptr]()

    init(mesh: MDLMesh,
         with vertexDescriptor: MDLVertexDescriptor)
    {
        self.mdlMesh = mesh
        setup(with: vertexDescriptor)
        assert(mesh.submeshes!.count == materialConstants.count)
        //print("# of submeshes:", indexBufferObjects.count)
        //print("# of materials:", materialConstants.count)
        //print("# of textures:", textures.count)
    }

    deinit
    {
        glDeleteBuffers(GLsizei(indexBufferObjects.count), indexBufferObjects)
        glDeleteBuffers(1, &vertexBufferObject)
        glDeleteVertexArrays(1, &vertexArrayObject)
    }

    func setup(with vertexDescriptor: MDLVertexDescriptor)
    {
        glGenVertexArrays(1, &vertexArrayObject)
        glBindVertexArray(vertexArrayObject)
        let stride = (vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        // Only 1 VBO since the data of all vertex attibutes are inter-leaved.
        glGenBuffers(1, &vertexBufferObject)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBufferObject)

        // The geometry of all .OBJ files must have a position attribute
        let posAttr = vertexDescriptor.attributeNamed(MDLVertexAttributePosition)
        var offset = posAttr!.offset
        var ptr = UnsafeRawPointer(bitPattern: offset)
        var vertAttrParms = GLKVertexAttributeParametersFromModelIO(posAttr!.format)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(GLuint(0),                            // attribute
                              GLint(vertAttrParms.size),            // size
                              GLenum(vertAttrParms.type),           // type
                              GLboolean(vertAttrParms.normalized),  // don't normalize
                              GLsizei(stride),                      // stride
                              ptr)                                  // array buffer offset
        let normalAttr = vertexDescriptor.attributeNamed(MDLVertexAttributeNormal)
        offset = normalAttr!.offset
        ptr = UnsafeRawPointer(bitPattern: offset)
        vertAttrParms = GLKVertexAttributeParametersFromModelIO(normalAttr!.format)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(GLuint(1),                            // attribute
                              GLint(vertAttrParms.size),            // size
                              GLenum(vertAttrParms.type),           // type
                              GLboolean(vertAttrParms.normalized),  // don't normalize
                              GLsizei(stride),                      // stride
                              ptr)                                  // array buffer offset
        let texCoordAttr = vertexDescriptor.attributeNamed(MDLVertexAttributeTextureCoordinate)
        offset = texCoordAttr!.offset
        ptr = UnsafeRawPointer(bitPattern: offset)
        vertAttrParms = GLKVertexAttributeParametersFromModelIO(texCoordAttr!.format)
        glEnableVertexAttribArray(2)
        glVertexAttribPointer(GLuint(2),                            // attribute
                              GLint(vertAttrParms.size),            // size
                              GLenum(vertAttrParms.type),           // type
                              GLboolean(vertAttrParms.normalized),  // don't normalize
                              GLsizei(stride),                      // stride
                              ptr)                                  // array buffer offset
        let tangentAttr = vertexDescriptor.attributeNamed(MDLVertexAttributeTangent)
        offset = tangentAttr!.offset
        ptr = UnsafeRawPointer(bitPattern: offset)
        vertAttrParms = GLKVertexAttributeParametersFromModelIO(tangentAttr!.format)
        glEnableVertexAttribArray(3)
        glVertexAttribPointer(GLuint(3),                            // attribute
                             GLint(vertAttrParms.size),             // size
                             GLenum(vertAttrParms.type),            // type
                             GLboolean(vertAttrParms.normalized),   // don't normalize
                             GLsizei(stride),                       // stride
                             ptr)                                   // array buffer offset
        // Add bitangent if necessary

        let vertAttrData = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition)
        // Can we assume data is of type GLfloat?
        glBufferData(GLenum(GL_ARRAY_BUFFER),
                     stride * mdlMesh.vertexCount,
                     vertAttrData!.map.bytes,
                     GLenum(GL_STATIC_DRAW))
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        indexBufferObjects = [GLuint](repeating: 0,
                                      count: mdlMesh.submeshes!.count)

        let submeshes = mdlMesh.submeshes as! [MDLSubmesh]
        for i in 0..<submeshes.count {
            glGenBuffers(1, &indexBufferObjects[i])
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), indexBufferObjects[i])
            //print(submeshes[i].material)
            let texture = Textures(material: submeshes[i].material)
            let useTextures = UseTextures(hasColorTexture: texture.baseColor != nil ? 1 : 0,
                                          hasNormalTexture: texture.normal != nil ? 1 : 0,
                                          hasMetallicTexture: texture.metallic != nil ? 1 : 0,
                                          hasRoughnessTexture: texture.roughness != nil ? 1 : 0,
                                          hasAOTexture: texture.ao != nil ? 1 : 0)

            textures.append(texture)
            hasTextures.append(useTextures)

            let material_const = MaterialConstants(material: submeshes[i].material)
            materialConstants.append(material_const)
        }
        indexDataSize = [GLsizeiptr](repeating: 0,
                                     count: mdlMesh.submeshes!.count)
        indexCount = [GLsizei](repeating: 0,
                               count: mdlMesh.submeshes!.count)
        indexType = [GLenum](repeating: 0,
                             count: mdlMesh.submeshes!.count)

        var k = 0
        for submesh in submeshes {
            if (submesh.geometryType != .triangles) {
                print("Mesh must be made up of Triangles")
                exit(3)
            }
            let indexBuffer = submesh.indexBuffer
            if (submesh.indexType == MDLIndexBitDepth.uint8) {
                indexCount[k] = GLsizei(indexBuffer.length)
                indexType[k] = GLenum(GL_UNSIGNED_BYTE)
                indexDataSize[k] = MemoryLayout<GLubyte>.size
            }
            if (submesh.indexType == MDLIndexBitDepth.uint16) {
                indexCount[k] = GLsizei(indexBuffer.length/2)
                indexType[k] = GLenum(GL_UNSIGNED_SHORT)
                indexDataSize[k] = MemoryLayout<GLushort>.size
            }
            if (submesh.indexType == MDLIndexBitDepth.uint32) {
                indexCount[k] = GLsizei(indexBuffer.length/4)
                indexType[k] = GLenum(GL_UNSIGNED_INT)
                indexDataSize[k] = MemoryLayout<GLuint>.size
            }
            glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBufferObjects[k])
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                         GLsizeiptr(GLsizei(indexDataSize[k]) * indexCount[k]),
                         indexBuffer.map().bytes,
                         GLenum(GL_STATIC_DRAW))
            k += 1
        }
        glBindVertexArray(0)
    }

    /// Assume the GLSL program is already in use.
    func draw(elapsedTime: Double,
              program glslProgram: GLuint)
    {
        // Pass the node's worldTransform to the vertex shader
        let modelMatrixLoc = glGetUniformLocation(glslProgram, "uModelMatrix")
        glUniformMatrix4fv(modelMatrixLoc,
                           1,
                           GLboolean(GL_FALSE),
                           worldTransform.array)
        glBindVertexArray(vertexArrayObject)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBufferObject)
        // Draw each submesh
        // Submeshes can have a combination of textures and materials
        for i in 0..<indexBufferObjects.count {
            let useTexture = hasTextures[i]
            let hasColorTextureLoc = glGetUniformLocation(glslProgram, "useTexture.hasColorTexture")
            let hasNormalTextureLoc = glGetUniformLocation(glslProgram, "useTexture.hasNormalTexture")
            let hasMetallicTextureLoc = glGetUniformLocation(glslProgram, "useTexture.hasMetallicTexture")
            let hasRoughnessTextureLoc = glGetUniformLocation(glslProgram, "useTexture.hasRoughnessTexture")
            let hasAOTextureLoc = glGetUniformLocation(glslProgram, "useTexture.hasAOTexture")
 
            var flag: GLint = useTexture.hasColorTexture == UInt32(1) ? 1 : 0
            glUniform1i(hasColorTextureLoc, flag)
            flag = useTexture.hasNormalTexture == UInt32(1) ? 1 : 0
            glUniform1i(hasNormalTextureLoc, flag)
            flag = useTexture.hasMetallicTexture == UInt32(1) ? 1 : 0
            glUniform1i(hasMetallicTextureLoc, flag)
            flag = useTexture.hasRoughnessTexture == UInt32(1) ? 1 : 0
            glUniform1i(hasRoughnessTextureLoc, flag)
            flag = useTexture.hasAOTexture == UInt32(1) ? 1 : 0
            glUniform1i(hasAOTextureLoc, flag)

            // Each submesh has its own set of Textures
            if textures[i].baseColor != nil {
                let baseColourTextureLoc =  glGetUniformLocation(glslProgram, "baseColourTexture")
                glUniform1i(baseColourTextureLoc, 0)
                glActiveTexture(GLenum(GL_TEXTURE0))
                glBindTexture(GLenum(GL_TEXTURE_2D), (textures[i].baseColor?.name)!)
            }
            if textures[i].normal != nil {
                let normalTextureLoc =  glGetUniformLocation(glslProgram, "normalTexture")
                glUniform1i(normalTextureLoc, 1)
                glActiveTexture(GLenum(GL_TEXTURE1))
                glBindTexture(GLenum(GL_TEXTURE_2D), (textures[i].normal?.name)!)
            }
            if textures[i].metallic != nil {
                let metallicTextureLoc =  glGetUniformLocation(glslProgram, "metallicTexture")
                glUniform1i(metallicTextureLoc, 2)
                glActiveTexture(GLenum(GL_TEXTURE2))
                glBindTexture(GLenum(GL_TEXTURE_2D), (textures[i].metallic?.name)!)
            }
            if textures[i].roughness != nil {
                let roughnessTextureLoc =  glGetUniformLocation(glslProgram, "roughnessTexture")
                glUniform1i(roughnessTextureLoc, 3)
                glActiveTexture(GLenum(GL_TEXTURE3))
                glBindTexture(GLenum(GL_TEXTURE_2D), (textures[i].roughness?.name)!)
            }
            if textures[i].ao != nil {
                let aoTextureLoc =  glGetUniformLocation(glslProgram, "aoTexture")
                glUniform1i(aoTextureLoc, 4)
                glActiveTexture(GLenum(GL_TEXTURE4))
                glBindTexture(GLenum(GL_TEXTURE_2D), (textures[i].ao?.name)!)
            }

            // Each submesh can have its own set of materials.
            let baseColorLoc = glGetUniformLocation(glslProgram, "materialConstants.baseColor")
            glUniform3fv(baseColorLoc, 1, materialConstants[i].baseColor.toArray())
            let specularColorLoc = glGetUniformLocation(glslProgram, "materialConstants.specularColor")
            glUniform3fv(specularColorLoc, 1, materialConstants[i].specularColor.toArray())
            let ambientColorLoc = glGetUniformLocation(glslProgram, "materialConstants.ambientColor")
            glUniform3fv(ambientColorLoc, 1, materialConstants[i].ambientColor.toArray())
            let ambientOcclusionLoc = glGetUniformLocation(glslProgram, "materialConstants.ambientOcclusion")
            glUniform3fv(ambientOcclusionLoc, 1, materialConstants[i].ambientOcclusion.toArray())
            let roughnessLoc = glGetUniformLocation(glslProgram, "materialConstants.roughness")
            glUniform1f(roughnessLoc, materialConstants[i].roughness)
            let metallicLoc = glGetUniformLocation(glslProgram, "materialConstants.metallic")
            glUniform1f(metallicLoc, materialConstants[i].metallic)
            let specularExponentLoc = glGetUniformLocation(glslProgram, "materialConstants.shininess")
            glUniform1f(specularExponentLoc, materialConstants[i].shininess)
            let opacityLoc = glGetUniformLocation(glslProgram, "materialConstants.opacity")
            glUniform1f(opacityLoc, materialConstants[i].opacity)

            glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                         indexBufferObjects[i])
            glDrawElements(GLenum(GL_TRIANGLES),
                           GLsizei(indexCount[i]),
                           indexType[i],            // e.g. GL_UNSIGNED_INT
                           nil)
        }
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), 0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        glBindVertexArray(0)
    }
}

