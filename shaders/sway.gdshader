shader_type canvas_item;
// Vítr: horní část spritu se jemně kolébá, spodek (kmen / kořeny) zůstává.
uniform float amp = 2.0;
uniform float speed = 1.4;
uniform float power = 1.6;

void vertex() {
	float k = pow(1.0 - UV.y, power);
	float ph = MODEL_MATRIX[3].x * 0.047 + MODEL_MATRIX[3].y * 0.031;
	VERTEX.x += (sin(TIME * speed + ph) + 0.4 * sin(TIME * speed * 2.3 + ph * 1.7)) * amp * k;
}
