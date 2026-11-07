shader_type spatial;
render_mode cull_disabled;
// 3D sprite objektu (strom, dům, keř…): jednotný vítr (větve a koruny se pohupují, dům ne), svítící okna v noci,
// mokro a sníh na střechách/korunách. Globální parametry nastavuje WorldFx.
global uniform float fx_wind;
global uniform float fx_wet;
global uniform float fx_snow;
global uniform float fx_glow;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : source_color, filter_linear, repeat_disable;
uniform float sway : hint_range(0.0, 1.0) = 0.0;       // 0 = pevné (domy), 1 = koruna stromu
uniform vec3 tint = vec3(1.0);                           // odchylka barvy jednotlivé instance
uniform float phase = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.58, 0.22);

void vertex() {
	float h = 1.0 - UV.y;                        // 0 u paty, 1 na vrcholu
	float t = TIME * (1.1 + fx_wind * 1.2) + phase;
	float gust = sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.4;
	VERTEX.x += gust * sway * h * h * (0.015 + fx_wind * 0.09);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	vec3 col = c.rgb * tint;
	col *= 1.0 - 0.18 * fx_wet;
	float top = smoothstep(0.38, 0.0, UV.y);
	col = mix(col, vec3(0.93, 0.96, 1.0), fx_snow * top * 0.75 * step(0.01, sway + 0.5));
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.7, fx_wet);
	SPECULAR = 0.0;
	float g = texture(glow_tex, UV).r;
	float flicker = 0.92 + 0.08 * sin(TIME * 7.0 + phase * 3.0);
	EMISSION = glow_color * (0.35 + col * 1.6) * g * fx_glow * flicker * 0.8;
}
