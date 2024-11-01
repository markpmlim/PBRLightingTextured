
in vec3 worldPosition;          // not normalised interpolated value
in vec3 worldNormal;            // interpolated value
in vec2 vST;


#define M_PI 3.141592653589793

struct UseTextures {
    bool hasColorTexture;
    bool hasNormalTexture;
    bool hasMetallicTexture;
    bool hasRoughnessTexture;
    bool hasAOTexture;
};

uniform UseTextures useTexture;

// Can this be encapsulate with the std140 layout? No
uniform sampler2D baseColourTexture;    // map_Kd
uniform sampler2D normalTexture;        // map_tangentSpaceNormal/map_bump
uniform sampler2D metallicTexture;      // map_metallic
uniform sampler2D roughnessTexture;     // map_roughness
uniform sampler2D aoTexture;            // map_ao

struct MaterialConstants {
    vec3 baseColor;         // Kd
    vec3 specularColor;     // Ks
    vec3 ambientColor;      // Ka (or Ke emission)
    vec3 ambientOcclusion;  // ao
    float roughness;        // roughness
    float metallic;         // metallic
    float shininess;        // Ns
    float opacity;          // d
};

uniform MaterialConstants materialConstants;
// We assume the light positions are already in world space.
uniform vec3 lightPositions[4];
uniform vec3 lightColors[4];
uniform vec3 cameraPos;

out vec4 fFragColor;

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = M_PI * denom * denom;

    return nom / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

// ----------------------------------------------------------------------------
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// ----------------------------------------------------------------------------
vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0),
                                 5.0);
}

vec3 getNormalFromMap()
{
    // Normal in tangent space; convert [0.0, 1.0] --> [-1.0, 1.0]
    vec3 tangentNormal = texture(normalTexture, vST).xyz * 2.0 - 1.0;

    // Compute the rate of change in x and y directions.
    vec3 Q1  = dFdx(worldPosition);
    vec3 Q2  = dFdy(worldPosition);
    vec2 st1 = dFdx(vST);
    vec2 st2 = dFdy(vST);

    vec3 N  = normalize(worldNormal);
    vec3 T  = normalize(Q1*st2.t - Q2*st1.t);
    vec3 B  = -normalize(cross(N, T));
    mat3 TBN = mat3(T, B, N);

    // Return world space normal
    return normalize(TBN * tangentNormal);
}

void main( )
{
    vec3 albedo = vec3(0);
    if (useTexture.hasColorTexture) {
        // Convert the albedo texture from sRGB to linear RGB
        albedo = pow(texture(baseColourTexture, vST).rgb, vec3(2.2));
    }
    else {
        albedo = materialConstants.baseColor;
    }

    float metallic = 0.0;
    if (useTexture.hasMetallicTexture) {
        metallic = texture(metallicTexture, vST).r;
    }
    else {
        metallic = materialConstants.metallic;
    }

    float roughness = 0.0;
    if (useTexture.hasRoughnessTexture) {
        roughness = texture(roughnessTexture, vST).r;
    }
    else {
        roughness = materialConstants.roughness;
    }

    float ao = 0.0;
    if (useTexture.hasAOTexture) {
        ao = texture(aoTexture, vST).r;
    }
    else {
        ao = 1.0;
    }

    vec3 N = getNormalFromMap();
    vec3 V = normalize(cameraPos - worldPosition);
    
    // Assume a dielectric surface
    vec3 F0 = vec3(0.04);
    // Interpolate between F0 and the albedo color.
    F0 = mix(F0, albedo,
             metallic);
    vec3 Lo = vec3(0.0);

    // For each light source, compute the radiance
    for(int i = 0; i < 4; ++i) {
        // Compute the light vector from the point of interest to the light source in world space.
        vec3 L = normalize(lightPositions[i] - worldPosition);
        vec3 H = normalize(L + V);          // half-way vector

        float dist = length(lightPositions[i] - worldPosition);
        // Apply the inverse square law to attenuate the light source.
        float attenuation = 1.0 / (dist * dist);
        // Calculate per-light radiance
        vec3 radiance = lightColors[i] * attenuation;

        // Cook-Torrance BRDF
        float NDF = DistributionGGX(N, H, roughness);
        float   G = GeometrySmith(N, V, L, roughness);
        vec3    F = fresnelSchlick(max(dot(H, V), 0.0), F0);

        vec3    numerator = NDF * G * F;
        // Add 0.001 to prevent division by zero.
        float denominator = 4 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001;

        vec3 specular = numerator / denominator;
        vec3 kS = F;                // specular contribution
        vec3 kD = vec3(1.0) - kS;   // refraction ratio
        // Multiply kD by the inverse metalness such that only non-metals
        // have diffuse lighting, or a linear blend if partly metal (pure metals
        // have no diffuse light).
        kD *= 1.0 - metallic;

        float nDotl = max(0.001, dot(N, L));

        // Add to outgoing radiance Lo
        // Note that we already multiplied the BRDF by the Fresnel (kS) so we won't multiply by kS again
        Lo += (kD * albedo / M_PI + specular) * radiance * nDotl;
    }

    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo;

    // Note: PBR requires all inputs to be in linear color space.
    // First, perform HDR tonemapping ...
    color = color / (color + vec3(1.0));
    // ... then gamma correct
    color = pow(color, vec3(1.0/2.2));

    fFragColor = vec4(color, 1.0);
}
