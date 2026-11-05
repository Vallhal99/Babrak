shader_type canvas_item;
// Celoobrazovkový post-processing: tilt-shift rozostření, bloom (záře), barevný grading, vinětace.
// Čte obraz přes hint_screen_texture -> funguje ve všech rendererech (Compatibility, Forward+, Mobile).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms tilt_shift;
uniform float tilt_px : hint_range(0.0, 8.0) = 2.2;      // max. rozostření (px) na okrajích
uniform float tilt_focus : hint_range(0.0, 1.0) = 0.5;   // svislá poloha ostré pásky
uniform float tilt_width : hint_range(0.0, 1.0) = 0.22;  // šířka ostré pásky

group_uniforms bloom;
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.28;
uniform float bloom_threshold : hint_range(0.0, 1.5) = 0.62;

group_uniforms grading;
uniform float saturation : hint_range(0.0, 2.0) = 1.02;
uniform float contrast : hint_range(0.5, 1.5) = 1.04;
uniform vec3 gain : source_color = vec3(1.0);            // barva světel (teplá/studená)
uniform vec3 shadow_tint : source_color = vec3(0.92, 0.95, 1.0); // barva stínů
uniform float vignette : hint_range(0.0, 1.0) = 0.4;

vec3 sample_blur(vec2 uv, float r, vec2 pxsize) {
	vec2 px = pxsize * r;
	vec3 c = texture(screen_tex, uv).rgb * 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982;
		c += texture(screen_tex, uv + vec2(cos(a), sin(a)) * px).rgb * 0.1;
	}
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float off = smoothstep(tilt_width, tilt_width + 0.4, abs(uv.y - tilt_focus));
	vec3 col = tilt_px > 0.05 ? sample_blur(uv, tilt_px * off, SCREEN_PIXEL_SIZE) : texture(screen_tex, uv).rgb;

	// bloom: jasné části z vyšších mipmap
	vec3 glow = vec3(0.0);
	for (int l = 2; l <= 5; l++) {
		vec3 s = textureLod(screen_tex, uv, float(l)).rgb;
		glow += max(s - vec3(bloom_threshold), 0.0);
	}
	col += glow * 0.5 * bloom_strength;

	// grading: stíny/světla, kontrast, saturace
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(shadow_tint, gain, smoothstep(0.1, 0.8, lum));
	col = (col - 0.5) * contrast + 0.5;
	lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);

	vec2 p = (uv - 0.5) * vec2(1.0, 1.1);
	col *= 1.0 - smoothstep(0.3, 0.9, length(p)) * vignette;
	COLOR = vec4(max(col, 0.0), 1.0);
}
