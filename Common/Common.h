//
//  Common.h
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.
//

#ifndef Common_h
#define Common_h

typedef struct {
    vector_float3 baseColor;            // Kd
    vector_float3 specularColor;        // Ks
    vector_float3 ambientColor;         // Ka (emission)
    vector_float3 ambientOcclusion;     // ao
    float roughness;                    // roughness
    float metallic;                     // metallic
    float shininess;                    // Ns
    float opacity;                      // d
} MaterialConstants;

#endif /* Common_h */
