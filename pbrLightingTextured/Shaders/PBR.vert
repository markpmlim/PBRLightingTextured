
layout (location = 0) in vec3 mcVertex;
layout (location = 1) in vec3 mcNormal;
layout (location = 2) in vec2 mcTexCoord0;
layout (location = 3) in vec4 mcTangent;        // unused

out vec3 worldPosition;         // not normalised
out vec3 worldNormal;           // normalised
out vec2 vST;

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;
uniform mat3 uNormalMatrix;

void main( )
{
    // Calculate vertex position in world space.
    worldPosition = vec3(uModelMatrix * vec4(mcVertex, 1.0));

    // Calculate normal (N) vectors in world space from incoming object/model space vectors.
    // Append a 0 to mcNormal because it is a vector not a position.
    worldNormal = normalize(vec3(uModelMatrix * vec4(mcNormal, 0.0)));

    // The worldNormal vector can also be transformed using one of the statements below
    // as long as there is no shearing or non-uniform scaling.
    //worldNormal = normalize(uNormalMatrix * mcNormal);
    //worldNormal = normalize(mat3(uModelMatrix) * mcNormal);

    vST = mcTexCoord0.st;
    // Transform to clip space.
    gl_Position = uProjectionMatrix * uViewMatrix * uModelMatrix * vec4(mcVertex, 1.0);
}
