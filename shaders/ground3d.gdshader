shader_type spatial;
// Země HD-2D světa: vykreslený podklad (viewport) + animovaná voda (vlnky, pěna u břehu, odlesky slunce),
// mokrý povrch (louže s odrazem oblohy a kruhy od deště), sníh a mech/listí v lese.
// Masky (zones.png, 1 px = 1 dlaždice, kryje celou mapu): R = voda, G = nálada oblasti, B = vlhkost břehu.
uniform sampler2D ground_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D zones_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sky_color : source_color = vec3(0.5, 0.6, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_power = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float water_motion : hint_range(0.0, 2.0) = 1.0;
uniform vec2 world_size = vec2(88.0, 72.0);   // rozměr mapy v metrech (pro vzorkování šumu)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// kruhy od dopadu kapek: mřížka buněk, každá má kapku s vlastní fází
float ripples(vec2 p, float t) {
	vec2 g = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash21(g);
	float ph = fract(t * 0.9 + h);
	float r = length(f);
	float ring = smoothstep(0.06, 0.0, abs(r - ph * 0.5)) * (1.0 - ph);
	return ring * step(0.35, h);
}

void fragment() {
	vec3 z = texture(zones_tex, UV).rgb;
	vec2 wp = UV * world_size;
	float t = TIME * water_motion;
	float water = smoothstep(0.25, 0.75, z.r);
	vec2 n1 = texture(noise_tex, wp * 0.07 + vec2(t * 0.02, t * 0.012)).rg;
	vec2 n2 = texture(noise_tex, wp * 0.16 - vec2(t * 0.03, -t * 0.02)).rg;

	// refrakce: voda mírně zkresluje podklad
	vec2 uv = UV + ((n1 - 0.5) + (n2 - 0.5) * 0.6) * 0.0016 * water;
	vec3 col = texture(ground_tex, uv).rgb;
	float rough = 0.95;
	float spec = 0.0;
	vec3 emis = vec3(0.0);

	// voda: vlnění, pěna na břehu, třpyt slunce
	if (water > 0.01) {
		float wave = n1.r * 0.6 + n2.g * 0.4;
		col *= 0.9 + wave * 0.25;
		float edge = smoothstep(0.88, 0.4, z.r) * water;                  // pás těsně u hranice vody
		float foam_n = texture(noise_tex, wp * 0.5 + vec2(t * 0.05, 0.0)).r;
		float foam = edge * smoothstep(0.42, 0.7, foam_n + 0.25 * sin(t * 1.6 + wp.x * 3.0));
		col = mix(col, vec3(0.92, 0.96, 1.0), clamp(foam, 0.0, 1.0) * 0.8);
		float gl = texture(noise_tex, wp * 0.9 + vec2(t * 0.11, -t * 0.07)).g;
		float glint = smoothstep(0.78, 0.9, gl * (0.6 + n2.r * 0.6));
		emis += sun_color * glint * 0.6 * sun_power;
		rough = 0.25;
		spec = 0.5;
		// nebe se zrcadlí do vody
		col = mix(col, sky_color * 0.8, 0.12 * water);
	}

	// mech a listí v lese (nálada 1 = G ≈ 50/255)
	float forest = smoothstep(0.1, 0.2, z.g) * (1.0 - smoothstep(0.25, 0.35, z.g));
	float patch = texture(noise_tex, wp * 0.22).b;
	col = mix(col, col * vec3(0.78, 1.0, 0.7), forest * smoothstep(0.5, 0.75, patch) * 0.55 * (1.0 - water));
	float litter = smoothstep(0.62, 0.8, texture(noise_tex, wp * 0.45 + 7.0).r);
	col = mix(col, vec3(0.45, 0.3, 0.14), forest * litter * 0.35 * (1.0 - water));

	// mokro: tmavší povrch, louže s odrazem a kruhy od kapek
	float dry = 1.0 - water;
	float wet = wetness * dry;
	float puddle_n = texture(noise_tex, wp * 0.05 + 3.0).r * 0.7 + texture(noise_tex, wp * 0.21).g * 0.3;
	float puddle = smoothstep(0.5, 0.62, puddle_n + z.b * 0.2) * wet;
	col *= 1.0 - 0.28 * wet;
	rough = mix(rough, 0.5, wet * 0.8);
	rough = mix(rough, 0.04, puddle);
	spec = max(spec, puddle * 0.9);
	col = mix(col, col * 0.55, puddle);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	emis += sky_color * puddle * (0.18 + fres * 0.6);
	float rp = ripples(wp * 9.0, TIME) + ripples(wp * 9.0 + 17.3, TIME * 1.13);
	emis += vec3(0.8, 0.9, 1.0) * rp * rain * max(puddle, water * 0.5) * 0.35;

	// sníh
	float sn = smoothstep(0.2, 0.55, texture(noise_tex, wp * 0.09 + 11.0).r + snow * 0.6 - 0.35) * snow * dry;
	col = mix(col, vec3(0.74, 0.78, 0.86), sn * 0.85);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
}
