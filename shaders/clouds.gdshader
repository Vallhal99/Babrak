shader_type canvas_item;
// Stíny mraků + mlha ve světových souřadnicích (pohybují se se světem, ne s kamerou).
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 cam_pos;
uniform float zoom = 1.0;
uniform vec2 wind = vec2(0.0);          // posun šumu (animuje skript)
uniform float cloud_density : hint_range(0.0, 1.0) = 0.22;
uniform float cloud_scale = 0.00055;
uniform vec4 cloud_color : source_color = vec4(0.05, 0.08, 0.16, 1.0);
uniform float fog_density : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.78, 0.84, 0.9, 1.0);

void fragment() {
	vec2 view = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 world = cam_pos + (FRAGCOORD.xy - view * 0.5) / zoom;
	float n = texture(noise_tex, world * cloud_scale + wind).r;
	float shade = smoothstep(0.5, 0.72, n) * cloud_density;
	float f = texture(noise_tex, world * cloud_scale * 2.3 - wind * 1.7 + 0.37).r;
	float fog = fog_density * (0.55 + 0.9 * f);
	float a = shade + fog * (1.0 - shade);
	vec3 rgb = (cloud_color.rgb * shade + fog_color.rgb * fog * (1.0 - shade)) / max(a, 0.001);
	COLOR = vec4(rgb, clamp(a, 0.0, 0.85));
}
