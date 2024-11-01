//
//  TexturesMaterials.swift
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa

// In GLSL, bool has a machine size of 4 bytes
// Reference: LearnOpenGL: Advanced GLSL - 29.6
struct UseTextures {
    var hasColorTexture: UInt32         // map_Kd
    var hasNormalTexture: UInt32        // map_tangentSpaceNormal/map_bump
    var hasMetallicTexture: UInt32      // map_metallic
    var hasRoughnessTexture: UInt32     // map_roughness
    var hasAOTexture: UInt32            // map_ao
}

class Textures
{
    var baseColor: GLKTextureInfo?
    var normal: GLKTextureInfo?
    var metallic: GLKTextureInfo?
    var roughness: GLKTextureInfo?
    var ao: GLKTextureInfo?

    init(material: MDLMaterial?)
    {
        if #available(macOS 10.13, iOS 11.0, *) {
            // For macOS 10.13 or later, use the property `urlValue` to get the 
            // url of the associated texture file.
            func property(with semantic: MDLMaterialSemantic) -> GLKTextureInfo? {
                guard
                    let property = material?.property(with: semantic),
                    property.type == .string,
                    let url = property.urlValue,
                    let textureInfo = try? Textures.loadTexture(from: url)
                else {
                    return nil
                }
                return textureInfo
            }
            baseColor = property(with: MDLMaterialSemantic.baseColor)
            normal = property(with: .tangentSpaceNormal)
            metallic = property(with: .metallic)
            roughness = property(with: .roughness)
            ao = property(with: .ambientOcclusion)
        }
        else {
            // For macOS 10.12 or earlier, use the property `stringValue` to get the
            // full pathname of the associated texture file.
            func property(with semantic: MDLMaterialSemantic) -> GLKTextureInfo? {
                guard
                    let property = material?.property(with: semantic),
                    property.type == .string,
                    let filename = property.stringValue,
                    let textureInfo = try? Textures.loadTexture(from: filename)
                else {
                    return nil
                }
                return textureInfo
            }
            baseColor = property(with: MDLMaterialSemantic.baseColor)
            normal = property(with: .tangentSpaceNormal)
            metallic = property(with: .metallic)
            roughness = property(with: .roughness)
            ao = property(with: .ambientOcclusion)
        }
    }

    static func loadTexture(from url: URL) throws -> GLKTextureInfo?
    {
        var textureInfo: GLKTextureInfo? = nil
        textureInfo = try GLKTextureLoader.texture(withContentsOf: url,
                                                   options: nil)
        return textureInfo
    }

    static func loadTexture(from pathname: String) throws -> GLKTextureInfo?
    {
        var textureInfo: GLKTextureInfo? = nil
        // Prepend the full pathname first.
        let urlString = "file://" + pathname
        guard let url = URL(string: urlString)
        else {
            return nil
        }
        textureInfo = try GLKTextureLoader.texture(withContentsOf: url,
                                                   options: nil)

        return textureInfo
    }
}

// Reference: Common.h for declaration of this struct.
extension MaterialConstants
{
    init(material: MDLMaterial?)
    {
        self.init()
        if let baseColor = material?.property(with: .baseColor),
            baseColor.type == .float3 {
            self.baseColor = baseColor.float3Value                  // Kd
            //Swift.print("Base Colour", self.baseColor)
        }
        if let specular = material?.property(with: .specular),
            specular.type == .float3 {
            self.specularColor = specular.float3Value               // Ks
            //Swift.print("Specular Color", self.specularColor)
        }
        if let emission = material?.property(with: .emission),
            emission.type == .float3 {
            self.ambientColor = emission.float3Value                // Ka (Ke)
            //Swift.print("ambientColor", self.ambientColor)
        }
        if let ambientOcclusion = material?.property(with: .ambientOcclusion),
            ambientOcclusion.type == .float3 {
            self.ambientOcclusion = ambientOcclusion.float3Value    // ao
            //Swift.print("ambientOcclusion", self.ambientOcclusion)
        }
        if let roughness = material?.property(with: .roughness),
            roughness.type == .float {
            self.roughness = roughness.floatValue
            //Swift.print("roughness", self.roughness)
        }
        if let metallic = material?.property(with: .metallic),
            metallic.type == .float {
            self.metallic = metallic.floatValue
            //Swift.print("metallic", self.metallic)
        }
        if let shininess = material?.property(with: .specularExponent), // Ns
            shininess.type == .float {
            self.shininess = shininess.floatValue
            //Swift.print("shininess", self.shininess)
        }
        if let opacity = material?.property(with: .opacity),            // d
            opacity.type == .float {
            self.opacity = opacity.floatValue
            //Swift.print("opacity:", self.opacity)
        }
    }
}
