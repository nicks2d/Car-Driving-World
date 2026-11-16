// Leuchten des Autos (CarModel): Scheinwerfer- und Rücklichtglas sowie eigene Blinkergläser.
// Blinker: Ein Bereich um den gemessenen Blinkerpunkt (indicator_point, linke Seite; rechts gespiegelt)
// leuchtet orange, solange der Blinker der Seite an ist. Bei eigenen Blinkergläsern (whole_part = 1) ist
// das ganze Teil Blinker, die Seite entscheidet x (links = +x).
// Lage im Auto: car_inverse rechnet Welt- in Auto-Koordinaten (x quer, y hoch, z nach vorne).
shader_type spatial;

uniform vec3 albedo_color : source_color = vec3(0.9, 0.92, 0.95);
// Leuchten des Glases (Scheinwerfer, Rücklicht, Bremslicht): Farbe und Stärke
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float glow = 0.15;
uniform mat4 car_inverse;
uniform vec3 indicator_point = vec3(0.0, -100.0, 0.0);
uniform float indicator_radius = 0.09;
uniform float whole_part = 0.0;
// Blinker links und rechts an (0 oder 1) und wie hell sie leuchten
uniform float left_lit = 0.0;
uniform float right_lit = 0.0;
uniform float indicator_glow = 5.0;

const vec3 AMBER = vec3(1.0, 0.34, 0.0);

varying vec3 car_pos;

void vertex() {
	car_pos = (car_inverse * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 innerhalb des Blinkerbereichs, weicher Rand
float area(vec3 point) {
	return smoothstep(indicator_radius, indicator_radius * 0.75, distance(car_pos, point));
}

void fragment() {
	float left = whole_part > 0.5 ? step(0.0, car_pos.x) : area(indicator_point);
	float right = whole_part > 0.5 ? step(car_pos.x, 0.0) : area(indicator_point * vec3(-1.0, 1.0, 1.0));
	float indicator = max(left, right);
	float lit = max(left * left_lit, right * right_lit);
	// Blinkerbereich leicht orange getönt, auch wenn er aus ist
	ALBEDO = mix(albedo_color, AMBER * 0.55, indicator * 0.5);
	EMISSION = glow_color * glow * (1.0 - indicator) + AMBER * indicator_glow * lit;
	ROUGHNESS = 0.2;
}
