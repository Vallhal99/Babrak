shader_type canvas_item;
uniform float strength = 0.45;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 1.1);
	float v = smoothstep(0.28, 0.85, length(p));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
