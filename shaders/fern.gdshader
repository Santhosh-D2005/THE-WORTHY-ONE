// Fern fronds and low leaves. Vertex colours carry the dark-root to light-tip gradient. A very gentle idle sway plus a short
// "gust" (driven from the script when a sword comes free) moves the tips; the root never moves. Cheap: no texture reads.
shader_type spatial;
// PERFORMANCE (measured on the Adreno 610, Milestone 1.9.2): the first version of this shader (per-pixel lighting, shadows,
// fog) cost 10-13 FPS because the overlapping fronds multiply the per-pixel work. Lighting is therefore per vertex, there is
// no specular, no shadow lookup and no per-pixel fog (the foliage is near the camera, where the haze is thin anyway; the far
// clumps are tinted toward the haze colour with the `tint` uniform instead).
render_mode cull_disabled, diffuse_lambert_wrap, vertex_lighting, specular_disabled, shadows_disabled, fog_disabled;

uniform float gust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.92, 0.98, 0.80);

void vertex() {
	float h = clamp(VERTEX.y, 0.0, 1.5);
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 1.3;
	float idle = sin(TIME * 1.3 + phase) * 0.012;
	float push = gust * sin(TIME * 6.0 + phase) * 0.05 + gust * 0.04;
	VERTEX.x += (idle + push) * h * h;
	VERTEX.z += (idle * 0.6 + push * 0.5) * h * h;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
