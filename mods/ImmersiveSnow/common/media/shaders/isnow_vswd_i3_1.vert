#version 330

// Immersive Snow: skinned variant of the vehicle snow shell, a copy of vanilla vehiclewheel.vert
// (same attribute layout as vehicle.vert, which renders non-static vehicle bodies).

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec3 vertViewNormal;
varying vec2 texCoords;
varying vec3 vertMeshPos;
varying float vertHeight;
layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec4 boneWeights;
layout (location = 3) in vec4 boneIndices;
layout (location = 4) in vec2 uv;

uniform mat4 ModelViewProjection;
uniform mat4 MatrixPalette[60];
uniform float targetDepth = 0.5;

// As in isnow_vehiclesnow_static.vert: n in the camera's rotation frame.
vec3 viewNormal(mat3 m, vec3 n)
{
	vec3 r0 = vec3(m[0][0], m[1][0], m[2][0]);
	vec3 r1 = vec3(m[0][1], m[1][1], m[2][1]);
	vec3 r2 = vec3(m[0][2], m[1][2], m[2][2]);
	return vec3(dot(r0, n) / length(r0), dot(r1, n) / length(r1), dot(r2, n) / length(r2));
}

// As in isnow_vehiclesnow_static.vert: mesh-space position in world units.
const float WORLD_PER_DEPTH = 212.132;

vec3 meshPos(mat3 m, vec3 p)
{
	return p * length(vec3(m[0][2], m[1][2], m[2][2])) * WORLD_PER_DEPTH;
}

// As in isnow_vehiclesnow_static.vert: height in world units above the model's origin.
const vec3 UP_VIEW = vec3(0.0, 0.8660254, -0.5);

float heightAbove(mat3 m, vec3 d)
{
	vec3 r0 = vec3(m[0][0], m[1][0], m[2][0]);
	vec3 r1 = vec3(m[0][1], m[1][1], m[2][1]);
	vec3 r2 = vec3(m[0][2], m[1][2], m[2][2]);
	vec3 v = vec3(d.x / length(r0), d.y / length(r1), d.z / length(r2));
	return dot(v, UP_VIEW) * length(r2) * WORLD_PER_DEPTH;
}

void main()
{
	vec4 position = vec4(vertex.xyz, 1.0);
	vec4 normal = vec4(normal.xyz, 0.0);

	texCoords = uv.st;

	mat4 boneEffect = mat4(0.0);
	if(boneWeights.x > 0.0)
		boneEffect += MatrixPalette[int(boneIndices.x)] * boneWeights.x;
	if(boneWeights.y > 0.0)
		boneEffect += MatrixPalette[int(boneIndices.y)] * boneWeights.y;
	if(boneWeights.z > 0.0)
		boneEffect += MatrixPalette[int(boneIndices.z)] * boneWeights.z;
	if(boneWeights.w > 0.0)
		boneEffect += MatrixPalette[int(boneIndices.w)] * boneWeights.w;

	normal = boneEffect * normal;
	vertNormal = normal.xyz;
	vertViewNormal = viewNormal(mat3(ModelViewProjection), normal.xyz);
	vertMeshPos = meshPos(mat3(ModelViewProjection * boneEffect), position.xyz);
	vertColour = vec3(1.0,1.0,1.0);

	vec4 o = ModelViewProjection * boneEffect * position;
	vertHeight = heightAbove(mat3(ModelViewProjection), o.xyz - (ModelViewProjection * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float clip = ((o.z+1.0) / 2.0); // -1,+1 -> 0,2 -> 0,1
	clip += targetDepth - 0.5;
	o.z = (clip*2)-1; // 0-1 -> 0-2 -> -1,+1

	gl_Position = o;
}
