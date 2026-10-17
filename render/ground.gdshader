shader_type spatial;
// Ground plane with metre and decimetre grid lines that fade with distance,
// so the player can always read scale.

uniform vec3 base_color : source_color = vec3(0.47, 0.56, 0.42);
uniform vec3 line_color : source_color = vec3(0.30, 0.38, 0.27);
uniform float fine_size = 0.1;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size) {
	vec2 g = p / size;
	vec2 w = fwidth(g);
	vec2 l = abs(fract(g - 0.5) - 0.5) / max(w, vec2(1e-5));
	return 1.0 - min(min(l.x, l.y), 1.0);
}

void fragment() {
	float dist = length(world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float major = grid(world_pos.xz, 1.0);
	float minor = grid(world_pos.xz, fine_size) * (1.0 - smoothstep(2.0, 12.0, dist));
	float line = max(major * (1.0 - smoothstep(30.0, 90.0, dist)), minor * 0.5);
	float noise = fract(sin(dot(floor(world_pos.xz * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = base_color * (0.96 + 0.06 * noise);
	ALBEDO = mix(col, line_color, line * 0.7);
	ROUGHNESS = 0.95;
}
