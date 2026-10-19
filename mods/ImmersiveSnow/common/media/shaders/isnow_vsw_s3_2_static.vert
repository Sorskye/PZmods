#version 330

// Immersive Snow: static variant of the vehicle snow shell, a copy of vanilla vehicle_static.vert
// (static vehicle bodies: uv at location 2).

out vec3 vertColour;
out vec3 vertNormal;
out vec3 vertViewNormal;
out vec2 texCoords;
out vec3 vertMeshPos;
out float vertHeight;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec2 uv;

uniform mat4 ModelViewProjection;
uniform mat4 transform;
uniform float targetDepth = 0.5;

// World units per unit of clip depth per mesh unit: Core.DoPushIsoStuff (called with true by
// VehicleModelCamera) sets ortho depth -10..10 (clip z = 0.1 * view z) and scales the view by
// Core.scale = sqrt(2) / 2 / 10 / 1.5 (tileScale / 2 = 1), whatever the zoom; so the length of
// the depth row of mat3(ModelViewProjection) is 0.1 * Core.scale * the mesh's world scale.
const float WORLD_PER_DEPTH = 212.132;
// World up in the frame of viewNormal, see isnow_vehiclesnow.frag
const vec3 UP_VIEW = vec3(0.0, 0.8660254, -0.5);

// Mesh-space position in world units (the mesh's scale taken from m, see WORLD_PER_DEPTH).
vec3 meshPos(mat3 m, vec3 p)
{
	return p * length(vec3(m[0][2], m[1][2], m[2][2])) * WORLD_PER_DEPTH;
}

// Normal n (model space) in the camera's rotation frame, see isnow_vehiclesnow.frag (UP_VIEW).
// m is the upper 3x3 of ModelViewProjection = orthographic scale * rotation * uniform scale, so
// its normalised rows are the rotation's rows (each signed like the projection's axis).
vec3 viewNormal(mat3 m, vec3 n)
{
	vec3 r0 = vec3(m[0][0], m[1][0], m[2][0]);
	vec3 r1 = vec3(m[0][1], m[1][1], m[2][1]);
	vec3 r2 = vec3(m[0][2], m[1][2], m[2][2]);
	return vec3(dot(r0, n) / length(r0), dot(r1, n) / length(r1), dot(r2, n) / length(r2));
}

// Height in world units above the model's origin of clip-space offset d from it: each clip axis
// divided by its row length of m is the camera-frame offset in mesh units, the depth row's length
// turns mesh units into world units (see WORLD_PER_DEPTH).
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
	vec4 position = vec4(vertex.xyz, 1);
	vec4 normal = vec4(normal.xyz, 0);

	texCoords = uv.st;

	vertNormal = (transform * normal).xyz;
	vertViewNormal = viewNormal(mat3(ModelViewProjection * transform), normal.xyz);
	vertMeshPos = meshPos(mat3(ModelViewProjection * transform), position.xyz);
	vertColour = vec3(1,1,1);

	vec4 o = ModelViewProjection * transform * position;
	vertHeight = heightAbove(mat3(ModelViewProjection * transform), o.xyz - (ModelViewProjection * transform * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float clip = ((o.z+1.0) / 2.0); // -1,+1 -> 0,2 -> 0,1
	clip += targetDepth - 0.5;
	o.z = (clip*2)-1; // 0-1 -> 0-2 -> -1,+1
	gl_Position = o;
}
