// Forest floor: three noise scales blend packed earth, leaf litter and mossy patches.
// World-space sampling, so it needs no UVs and tiles without visible repetition.
// 3 texture reads per pixel - cheap enough for mid-range mobile GPUs.
shader_type spatial;

uniform vec3 earth_color : source_color = vec3(0.10, 0.08, 0.05);
uniform vec3 litter_color : source_color = vec3(0.20, 0.15, 0.09);
uniform vec3 dry_leaf_color : source_color = vec3(0.30, 0.22, 0.11);
uniform vec3 moss_color : source_color = vec3(0.10, 0.17, 0.06);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float macro = texture(noise_tex, p * 0.035).r;
	float mid = texture(noise_tex, p * 0.22).r;
	float fine = texture(noise_tex, p * 1.9).r;

	// 1.9: earth, damp dark soil, brown leaf litter, a few warmer dry leaves and green moss - broader tonal range, same 3 reads.
	vec3 col = mix(earth_color, litter_color, smoothstep(0.30, 0.70, mid));
	col = mix(col, earth_color * 0.55, smoothstep(0.58, 0.80, macro) * (1.0 - smoothstep(0.5, 0.8, mid)) * 0.8);  // damp, dark soil
	col = mix(col, dry_leaf_color, smoothstep(0.62, 0.85, fine) * smoothstep(0.35, 0.6, mid) * 0.85);
	col = mix(col, dry_leaf_color * vec3(1.15, 0.8, 0.55), smoothstep(0.80, 0.93, fine) * smoothstep(0.45, 0.7, mid) * 0.6);   // rust-brown leaves
	col = mix(col, moss_color, smoothstep(0.50, 0.72, macro) * 0.9);
	col *= 0.62 + fine * 0.75;
	// Darker, damper ground close to the stump (the roots shade it) and a faint warm lift farther out in the sun.
	float stump_dist = length(p);
	col *= mix(0.78, 1.0, smoothstep(1.6, 4.0, stump_dist));

	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
}
