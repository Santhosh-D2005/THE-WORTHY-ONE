// A round tap target that looks like a slice of the forest: an end-grain wooden disc with a bark rim,
// moss patches, and a carved groove. No text, no symbols. Drawn on a square ColorRect (UV 0..1).
// Pressed state: the face sinks (darker, rings shift slightly toward the centre) and the groove catches a
// faint warm light. `glow` is the quiet pulse that marks the side to tap next.
// Cost: one small quad, 3 texture reads per pixel.
shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 seed_offset = vec2(0.0);       // moves the grain so the two discs are different slices
uniform float pressed : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float out_gamma = 1.0;             // ~1.3 when baked into a viewport texture (tone match)
uniform vec3 wood_light : source_color = vec3(0.58, 0.45, 0.29);
uniform vec3 wood_dark : source_color = vec3(0.33, 0.23, 0.14);
uniform vec3 bark_color : source_color = vec3(0.13, 0.095, 0.065);
uniform vec3 moss_color : source_color = vec3(0.14, 0.24, 0.08);
uniform vec3 warm_light : source_color = vec3(0.95, 0.78, 0.45);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r) * 1.5, 0.004);

	// Soft contact shadow around the disc, so it sits on the screen like an object on the ground.
	float shadow = (1.0 - smoothstep(0.90, 1.0, r)) * 0.5;
	float disc = 1.0 - smoothstep(0.90 - aa, 0.90 + aa, r);

	vec2 n_uv = p * 0.5 + 0.5 + seed_offset;
	float n_macro = texture(noise_tex, n_uv * 1.3).r;
	float n_mid = texture(noise_tex, n_uv * 3.1 + 0.37).r;
	float n_fine = texture(noise_tex, n_uv * 8.0).r;

	// Light from the top left.
	vec2 dir = r > 0.001 ? p / r : vec2(0.0);
	float lit = dot(dir, normalize(vec2(-0.6, -0.8)));

	// Bark rim (outer ring) with moss patches and a bevel.
	float bark_w = smoothstep(0.745 - aa, 0.745 + aa, r);
	vec3 bark = bark_color * (0.75 + n_fine * 0.7);
	bark = mix(bark, moss_color * (0.8 + n_mid * 0.6), smoothstep(0.52, 0.72, n_macro) * 0.8);
	bark *= 0.8 + 0.28 * lit * smoothstep(0.745, 0.9, r);

	// Carved groove between rim and face: a dark channel with a bright lip on its lower edge.
	float groove = 1.0 - smoothstep(0.0, 0.028, abs(r - 0.735));
	float lip = 1.0 - smoothstep(0.0, 0.016, abs(r - 0.712));

	// End-grain face. Pressing sinks it: the pattern is sampled slightly smaller and darker.
	float rr = r * (1.0 + 0.05 * pressed);
	float warp = (n_macro - 0.5) * 0.07 + (n_mid - 0.5) * 0.02;
	float ring_phase = fract((rr + warp) * 8.5);
	float ring = smoothstep(0.0, 0.5, ring_phase) * (1.0 - smoothstep(0.72, 1.0, ring_phase));
	vec3 face = mix(wood_dark, wood_light, ring * 0.8 + n_fine * 0.2);
	face *= 1.0 - 0.28 * pressed;
	face *= 0.92 + 0.08 * lit * smoothstep(0.3, 0.72, r);
	// A hairline radial check, like a drying crack, different on each disc.
	float ang = atan(p.y, p.x);
	float crack_n = texture(noise_tex, vec2(ang * 0.8 + seed_offset.x * 3.0, rr * 0.4)).r;
	float crack = (1.0 - smoothstep(0.0, 0.02, abs(crack_n - 0.5))) * smoothstep(0.2, 0.55, r) * (1.0 - bark_w);
	face = mix(face, wood_dark * 0.35, crack * 0.8);

	vec3 col = mix(face, bark, bark_w);
	col = mix(col, vec3(0.03, 0.02, 0.012), groove * 0.85);
	col += vec3(0.20, 0.15, 0.09) * lip * 0.35 * (1.0 - bark_w);
	// Warm light in the groove: faint when pressed, a quiet pulse when this is the side to tap next.
	float rim_glow = clamp(pressed * 0.55 + glow, 0.0, 1.0);
	col = mix(col, warm_light, groove * rim_glow * 0.75);
	col += warm_light * (1.0 - smoothstep(0.0, 0.1, abs(r - 0.76))) * rim_glow * 0.10;

	float alpha = max(disc, shadow * (1.0 - disc));
	vec3 rgb = mix(vec3(0.0), col, disc);
	COLOR = vec4(pow(rgb, vec3(out_gamma)), alpha);
}
