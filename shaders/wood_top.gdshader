// Freshly cut stump surface: growth rings, radial checks (cracks), darker sword slot.
// Procedural placeholder - replace with a scanned/painted wood material later.
shader_type spatial;

uniform vec3 light_wood : source_color = vec3(0.64, 0.51, 0.35);
uniform vec3 dark_wood : source_color = vec3(0.40, 0.29, 0.18);
uniform float stump_radius = 1.25;
uniform float ring_count = 17.0;
uniform float slot_radius = 0.11;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// 1.12/1.13: how far the wood has split (0..1, the extraction strain) and how bright the amber is inside the cracks (0..1).
uniform float crack_amount = 0.0;
uniform float crack_glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.46, 0.09);

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

void fragment() {
	vec2 p = local_xz / stump_radius;                 // -1..1 across the disc
	float warp = texture(noise_tex, p * 0.7 + 0.5).r; // wobble rings so they are not perfect circles
	float d = length(p) + (warp - 0.5) * 0.05;
	float ring_phase = fract(d * ring_count);
	float ring = smoothstep(0.0, 0.55, ring_phase) * (1.0 - smoothstep(0.7, 1.0, ring_phase));
	float fine = texture(noise_tex, p * 3.5).r;
	// 1.6: stronger ring contrast (0.75/0.25 -> 0.9/0.1) so the growth rings stay legible at the 0.6 render scale.
	vec3 col = mix(dark_wood, light_wood, ring * 0.9 + fine * 0.1);

	// 1.9: thin dark lines where each growth ring starts (the late wood), and a gentle warm gradient across the cut.
	float line = smoothstep(0.0, 0.06, ring_phase) * (1.0 - smoothstep(0.06, 0.16, ring_phase));
	col = mix(col, dark_wood * 0.62, (1.0 - line) * 0.0 + (1.0 - smoothstep(0.0, 0.1, ring_phase)) * 0.45);
	col *= 0.94 + 0.12 * smoothstep(-1.0, 1.0, p.x * 0.6 - p.y * 0.8);

	// Dark, aged outer ring near the bark.
	col = mix(col, dark_wood * 0.7, smoothstep(0.86, 1.0, length(p)));

	// 1.12: the placeholder's always-visible drying cracks are gone: at 0 % progress the cut is clean. Every crack now comes from
	// crack_amount below (the current extraction strain), so it opens and closes with the progress.
	float ang = atan(p.y, p.x);
	float crack_mask = 0.0;
	float crack_core = 0.0;
	float crack_halo = 0.0;
	if (crack_amount > 0.004) {
		float c = crack_amount;
		float r = length(p);
		float a = (ang + 3.14159265) ;                       // 0 .. TAU
		float cell = 6.2831853 / 9.0;                        // nine main cracks around the cut, at jittered angles
		int k = int(floor(a / cell));
		float width = mix(0.011, 0.030, smoothstep(0.2, 1.0, c));
		for (int o = -1; o <= 1; o++) {
			int kk = k + o;
			float id = float(((kk % 9) + 9) % 9);
			float h1 = fract(sin((id + 1.0) * 127.1) * 43758.5453);
			float h2 = fract(sin((id + 17.0) * 127.1) * 43758.5453);
			float h3 = fract(sin((id + 31.0) * 127.1) * 43758.5453);
			float h4 = fract(sin((id + 47.0) * 127.1) * 43758.5453);
			float h5 = fract(sin((id + 59.0) * 127.1) * 43758.5453);
			// The crack wanders a little (analytic, no texture).
			float wander = sin(r * 6.0 + id * 3.1) * 0.035 + sin(r * 15.0 + id * 1.7) * 0.012;
			float ca = (float(kk) + 0.2 + 0.6 * h1) * cell + wander;
			// Each crack has its own moment to start (about 12-30 %) and its own final length: they open one after another.
			float t_start = 0.05 + 0.20 * h2;
			float reach = clamp((c - t_start) * 2.0, 0.0, 1.0);
			float r_end = 0.10 + reach * (0.60 + 0.42 * h3 - 0.10);
			if (reach > 0.0) {
				float taper = smoothstep(0.10, 0.14, r) * (1.0 - smoothstep(r_end - 0.2 * (r_end - 0.10), r_end, r));
				float wt = width * mix(1.0, 0.35, smoothstep(0.10, max(r_end, 0.11), r));
				float d = abs(a - ca) * r;
				crack_halo = max(crack_halo, (1.0 - smoothstep(wt, wt * 3.5, d)) * taper);
				crack_mask = max(crack_mask, (1.0 - smoothstep(wt * 0.5, wt, d)) * taper);
				crack_core = max(crack_core, (1.0 - smoothstep(wt * 0.10, wt * 0.5, d)) * taper);
				// First fork (from about 50 %) and second fork (from about 70 %): branches that peel away from the main crack.
				float side = h5 > 0.5 ? 1.0 : -1.0;
				float len1 = clamp((c - (0.45 + 0.10 * h4)) * 2.0, 0.0, 1.0) * (0.20 + 0.22 * h5);
				float rb1 = min(0.28 + 0.25 * h4, r_end * 0.75);
				float len2 = clamp((c - (0.66 + 0.08 * h1)) * 2.2, 0.0, 1.0) * (0.16 + 0.20 * h3);
				float rb2 = min(0.50 + 0.20 * h2, r_end * 0.88);
				float e1 = rb1 + len1;
				float e2 = rb2 + len2;
				float t1 = smoothstep(rb1, rb1 + 0.03, r) * (1.0 - smoothstep(e1 - 0.2 * len1, e1, r)) * step(0.001, len1);
				float t2 = smoothstep(rb2, rb2 + 0.03, r) * (1.0 - smoothstep(e2 - 0.2 * len2, e2, r)) * step(0.001, len2);
				float d1 = abs(a - (ca + side * 0.6 * (r - rb1))) * r;
				float d2 = abs(a - (ca - side * 0.6 * (r - rb2))) * r;
				float w1 = wt * 0.65;
				float w2 = wt * 0.55;
				crack_mask = max(crack_mask, max((1.0 - smoothstep(w1 * 0.5, w1, d1)) * t1, (1.0 - smoothstep(w2 * 0.5, w2, d2)) * t2));
				crack_core = max(crack_core, max((1.0 - smoothstep(w1 * 0.10, w1 * 0.5, d1)) * t1 * 0.85, (1.0 - smoothstep(w2 * 0.10, w2 * 0.5, d2)) * t2 * 0.8));
			}
		}
		// The opening is dark, with a slightly lighter split-wood edge around it.
		col *= 1.0 - crack_halo * 0.30;  // the wood darkens a little around the split
		col = mix(col, vec3(0.04, 0.025, 0.015), crack_mask * 0.95);
	}

	// Slot where the blade enters the wood.
	float slot = 1.0 - smoothstep(slot_radius * 0.8, slot_radius * 1.6, length(local_xz));
	col = mix(col, vec3(0.03, 0.02, 0.015), slot);

	ALBEDO = col;
	if (crack_glow > 0.002) {
		// Quiet amber under the wood: only inside the crack cores, brighter toward the slot, a slow bounded breathing (+/- 6 %).
		float breathe = 1.0 + 0.06 * sin(TIME * 1.3 + length(p) * 6.0);
		EMISSION = glow_color * crack_core * crack_glow * breathe * 0.95 * (1.15 - 0.5 * length(p));
	}
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
}
