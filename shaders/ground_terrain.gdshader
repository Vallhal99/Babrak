shader_type canvas_item;
// Podklad z více terénů (až 8 na chunk): slot 0 = základ, sloty 1..7 se kreslí přes něj podle masek.
// Maska = 1 texel na dlaždici (2× RGBA), shader ji rozmaže a naruší šumem -> organické přechody.
// Šum se čte ze světových souřadnic, takže na hranicích chunků nejsou švy.
uniform sampler2D mask_a : filter_linear, repeat_disable;   // sloty 1..4 (RGBA)
uniform sampler2D mask_b : filter_linear, repeat_disable;   // sloty 5..7 (RGB)
uniform sampler2D tex0 : filter_nearest, repeat_enable;
uniform sampler2D tex1 : filter_nearest, repeat_enable;
uniform sampler2D tex2 : filter_nearest, repeat_enable;
uniform sampler2D tex3 : filter_nearest, repeat_enable;
uniform sampler2D tex4 : filter_nearest, repeat_enable;
uniform sampler2D tex5 : filter_nearest, repeat_enable;
uniform sampler2D tex6 : filter_nearest, repeat_enable;
uniform sampler2D tex7 : filter_nearest, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(1.0);
uniform float tile = 48.0;
uniform float edge_noise = 0.34;
uniform float blur_px = 34.0;
varying vec2 wp;

void vertex() { wp = VERTEX + rect_origin; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 tiled(sampler2D t, vec2 p) {
	vec2 c = floor(p / tile);
	vec2 f = fract(p / tile);
	float h = hash(c);
	if (h > 0.5) f.x = 1.0 - f.x;
	if (fract(h * 7.0) > 0.5) f.y = 1.0 - f.y;
	return texture(t, f).rgb;
}

vec4 blur_tex(sampler2D m, vec2 p) {
	vec2 uv = (p - mask_origin) / mask_size;
	vec2 o = vec2(blur_px) / mask_size;
	vec4 s = texture(m, uv) * 0.24;
	s += (texture(m, uv + vec2(o.x, 0.0)) + texture(m, uv - vec2(o.x, 0.0)) + texture(m, uv + vec2(0.0, o.y)) + texture(m, uv - vec2(0.0, o.y))) * 0.12;
	s += (texture(m, uv + o) + texture(m, uv - o) + texture(m, uv + vec2(o.x, -o.y)) + texture(m, uv + vec2(-o.x, o.y))) * 0.07;
	return s;
}

vec3 overlay(vec3 c, sampler2D t, float mv, float seed, float n2, float n3) {
	if (mv < 0.01) return c;                       // tento terén tu vůbec není
	float nn = texture(noise_tex, wp / 38.0 + vec2(seed * 0.37, seed * 0.61)).r;
	float m = mv + (nn - 0.5) * edge_noise + (n2 - 0.5) * edge_noise * 0.6;
	float d = smoothstep(0.47, 0.53, m);
	float rim = smoothstep(0.40, 0.55, m) - smoothstep(0.62, 0.92, m);
	vec3 col = tiled(t, wp);
	col *= 1.0 + (n2 - 0.5) * 0.18 + (n3 - 0.5) * 0.12;
	col *= 1.0 - 0.18 * rim;
	vec3 r = mix(c, col, d);
	return r * (1.0 - 0.10 * smoothstep(0.34, 0.5, m) * (1.0 - smoothstep(0.5, 0.62, m)));
}

void fragment() {
	float n1 = texture(noise_tex, wp / 520.0).r;
	float n2 = texture(noise_tex, wp / 150.0).r;
	float n3 = texture(noise_tex, wp / 38.0).r;
	vec4 a = blur_tex(mask_a, wp);
	vec4 b = blur_tex(mask_b, wp);

	vec3 c = tiled(tex0, wp);
	c *= 1.0 + (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.14;
	c.r *= 1.0 + (n1 - 0.5) * 0.2;
	c.b *= 1.0 - (n1 - 0.5) * 0.2;
	float near = max(max(a.r, a.g), max(max(a.b, a.a), max(b.r, max(b.g, b.b))));
	c *= 1.0 - 0.16 * smoothstep(0.18, 0.46, near) * (1.0 - smoothstep(0.47, 0.53, near));

	c = overlay(c, tex1, a.r, 1.0, n2, n3);
	c = overlay(c, tex2, a.g, 2.0, n2, n3);
	c = overlay(c, tex3, a.b, 3.0, n2, n3);
	c = overlay(c, tex4, a.a, 4.0, n2, n3);
	c = overlay(c, tex5, b.r, 5.0, n2, n3);
	c = overlay(c, tex6, b.g, 6.0, n2, n3);
	c = overlay(c, tex7, b.b, 7.0, n2, n3);
	COLOR = vec4(c, 1.0);
}
