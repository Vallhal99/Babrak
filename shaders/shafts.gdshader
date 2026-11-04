shader_type canvas_item;
render_mode blend_add;
// Sluneční paprsky přes koruny stromů (přes celou obrazovku, jen ve dne).
uniform float strength = 0.0;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

void fragment() {
	float diag = UV.x * 0.8 + UV.y * 0.45;
	float band = sin(diag * 19.0 + TIME * 0.12 + texture(noise_tex, UV * 0.6).r * 3.5) * 0.5 + 0.5;
	band = smoothstep(0.62, 1.0, band);
	float fade = clamp(1.0 - (UV.x * 0.5 + UV.y * 0.95) * 0.8, 0.0, 1.0);
	COLOR = vec4(vec3(1.0, 0.92, 0.68) * band * fade * strength * 0.32, 1.0);
}
