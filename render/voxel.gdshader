shader_type spatial;
// Material for voxel chunks. Faces of deeper objects in the object tree are
// nudged slightly toward the camera, so where a child and an ancestor have
// faces in the same plane the child always wins instead of z-fighting.

// Depth of the rendered instance in the object tree (World = 0), set per
// MeshInstance3D so instances keep sharing one mesh.
instance uniform float layer = 0.0;
// Fraction of the view distance each layer moves toward the camera.
uniform float bias_per_layer = 0.00001;
uniform float roughness_value = 0.88;

void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Godot 4.3+ uses reversed Z (near = 1, far = 0) with a float depth
	// buffer, whose precision is relative; scaling z moves the face closer by
	// a constant fraction of its distance.
	POSITION.z *= 1.0 + layer * bias_per_layer;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = roughness_value;
}
