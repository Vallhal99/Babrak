shader_type canvas_item;
// Podklad: tráva + hlína. Přechod z masky (rozmazané) + šumu = organická hranice, bez dlaždicového vzhledu.
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D grass_tex : filter_nearest, repeat_enable;
uniform sampler2D dirt_tex : filter_nearest, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 world_size = vec2(1536.0, 1152.0);
uniform float tile = 48.0;
uniform float edge_noise = 0.34;
varying vec2 wp;

void vertex() { wp = VERTEX; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// dlaždice s náhodným překlopením po buňkách (ruší opakování)
vec3 tiled(sampler2D t, vec2 p) {
	vec2 c = floor(p / tile);
	vec2 f = fract(p / tile);
	float h = hash(c);
	if (h > 0.5) f.x = 1.0 - f.x;
	if (fract(h * 7.0) > 0.5) f.y = 1.0 - f.y;
	return texture(t, f).rgb;
}

void fragment() {
	float n1 = texture(noise_tex, wp / 520.0).r;
	float n2 = texture(noise_tex, wp / 150.0).r;
	float n3 = texture(noise_tex, wp / 38.0).r;
	float raw = texture(mask_tex, wp / world_size).r;
	float m = raw + (n3 - 0.5) * edge_noise + (n2 - 0.5) * edge_noise * 0.6;
	float d = smoothstep(0.47, 0.53, m);
	float rim = smoothstep(0.40, 0.55, m) - smoothstep(0.62, 0.92, m);

	vec3 g = tiled(grass_tex, wp);
	g *= 1.0 + (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.14;
	g.r *= 1.0 + (n1 - 0.5) * 0.2;
	g.b *= 1.0 - (n1 - 0.5) * 0.2;
	g *= 1.0 - 0.16 * smoothstep(0.18, 0.46, m) * (1.0 - d);   // sytější tráva u hlíny

	vec3 dt = tiled(dirt_tex, wp);
	dt *= 1.0 + (n2 - 0.5) * 0.18 + (n3 - 0.5) * 0.12;
	dt *= 1.0 - 0.18 * rim;                                    // ušlapaný tmavší okraj
	vec3 c = mix(g, dt, d);
	c *= 1.0 - 0.10 * smoothstep(0.34, 0.5, m) * (1.0 - smoothstep(0.5, 0.62, m));  // stínová hrana
	COLOR = vec4(c, 1.0);
}
