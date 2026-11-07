shader_type spatial;
// Pohybující se stíny mraků na zemi (průhledná tmavá vrstva). Síla = profil osvětlení (přes den, v noci skoro nic).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.4;
uniform float scale = 0.018;
uniform vec2 wind = vec2(0.010, 0.004);
uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.8);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wp.xz * scale + wind * TIME).r;
	float c = smoothstep(0.5, 0.72, n);
	ALBEDO = tint * 0.35;
	ALPHA = c * strength * 0.5;
}
