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

group_uniforms fx;
uniform float shafts : hint_range(0.0, 1.0) = 0.0;       // god rays (radiální rozmazání k slunci)
uniform vec2 sun_uv = vec2(0.5, -0.2);
uniform vec3 shaft_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float grain : hint_range(0.0, 1.0) = 0.0;        // filmové zrno
uniform float chroma : hint_range(0.0, 1.0) = 0.0;       // chromatická aberace na okrajích
uniform float flash : hint_range(0.0, 1.0) = 0.0;        // záblesk (blesk)
uniform float focus_amount : hint_range(0.0, 1.0) = 0.0; // dialog: rozostření okolí postavy
uniform vec2 focus_uv = vec2(0.5, 0.5);
uniform float lut_mix : hint_range(0.0, 1.0) = 0.0;      // barevná nálada oblasti
uniform sampler2D lut_a : filter_linear, repeat_disable;
uniform sampler2D lut_b : filter_linear, repeat_disable;
uniform float lut_blend : hint_range(0.0, 1.0) = 0.0;    // přechod A -> B při změně oblasti

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

// 3D LUT uložená jako pásek 16 řezů (256x16)
vec3 lut_sample(sampler2D t, vec3 c) {
	c = clamp(c, 0.0, 1.0) * 15.0;
	float b = floor(c.b);
	float b2 = min(b + 1.0, 15.0);
	vec2 uv1 = vec2((b * 16.0 + c.r + 0.5) / 256.0, (c.g + 0.5) / 16.0);
	vec2 uv2 = vec2((b2 * 16.0 + c.r + 0.5) / 256.0, (c.g + 0.5) / 16.0);
	return mix(texture(t, uv1).rgb, texture(t, uv2).rgb, c.b - b);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float off = smoothstep(tilt_width, tilt_width + 0.4, abs(uv.y - tilt_focus));
	// dialog: okolí postavy se rozostří, střed zůstane ostrý
	off = max(off, focus_amount * smoothstep(0.12, 0.5, distance((uv - focus_uv) * vec2(1.4, 1.0), vec2(0.0))));
	float blur_r = max(tilt_px * off, focus_amount * 3.0 * off);
	// chromatická aberace: kanály R/B se posouvají od středu
	vec2 dir = (uv - 0.5);
	float ca = chroma * 0.0022 * dot(dir, dir) * 4.0;
	vec3 col = blur_r > 0.05 ? sample_blur(uv, blur_r, SCREEN_PIXEL_SIZE) : texture(screen_tex, uv).rgb;
	if (ca > 0.00002) {
		col.r = texture(screen_tex, uv + dir * ca * 6.0).r * 0.5 + col.r * 0.5;
		col.b = texture(screen_tex, uv - dir * ca * 6.0).b * 0.5 + col.b * 0.5;
	}

	// god rays: světlé části rozmazané směrem ke slunci
	if (shafts > 0.001) {
		vec2 step_v = (sun_uv - uv) / 14.0;
		vec2 p = uv + step_v * hash12(uv * 977.0);
		vec3 acc = vec3(0.0);
		float w = 1.0;
		for (int i = 0; i < 14; i++) {
			vec3 s = textureLod(screen_tex, p, 1.0).rgb;
			acc += max(s - vec3(0.55), 0.0) * w;
			w *= 0.93;
			p += step_v;
		}
		col += acc / 14.0 * shaft_color * shafts * 1.6;
	}

	// bloom: jasné části z vyšších mipmap
	vec3 glow = vec3(0.0);
	for (int l = 2; l <= 5; l++) {
		vec3 s = textureLod(screen_tex, uv, float(l)).rgb;
		glow += max(s - vec3(bloom_threshold), 0.0);
	}
	col += glow * 0.5 * bloom_strength;

	// barevná nálada oblasti (LUT)
	if (lut_mix > 0.001) {
		vec3 g = lut_sample(lut_a, col);
		g = mix(g, lut_sample(lut_b, col), lut_blend);
		col = mix(col, g, lut_mix);
	}

	// grading: stíny/světla, kontrast, saturace
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(shadow_tint, gain, smoothstep(0.1, 0.8, lum));
	col = (col - 0.5) * contrast + 0.5;
	lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);

	vec2 p = (uv - 0.5) * vec2(1.0, 1.1);
	col *= 1.0 - smoothstep(0.3, 0.9, length(p)) * vignette;
	col += flash * vec3(0.75, 0.82, 1.0);
	col += (hash12(uv * vec2(1920.0, 1080.0) + fract(TIME) * 100.0) - 0.5) * grain * 0.10;
	COLOR = vec4(max(col, 0.0), 1.0);
}
