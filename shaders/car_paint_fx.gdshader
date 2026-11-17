// Zusätzlicher Durchgang über dem Lack (CarModel, next_pass des Lacks): Wetter am Auto (CarWeather).
//  - Regentropfen als kleine glänzende Perlen; auf schrägen Flächen laufen sie, beim Fahren weht der
//    Fahrtwind sie nach hinten; nach dem Regen trocknen sie langsam (wet sinkt)
//  - Schnee auf nach oben zeigenden Flächen (Dach, Motorhaube, Kofferraum)
// Lage im Auto: car_inverse rechnet Welt- in Auto-Koordinaten, car_basis zurück (für die Normalen).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

#include "res://shaders/car_weather.gdshaderinc"

uniform mat4 car_inverse;
uniform mat3 car_basis;
uniform float car_speed = 0.0;
uniform float wet = 0.0;
uniform float snow = 0.0;
// Größe der Tropfen-Zellen auf dem Lack (Meter)
uniform float drop_cell = 0.03;

varying vec3 car_pos;
varying vec3 car_normal;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	car_pos = (car_inverse * vec4(world, 1.0)).xyz;
	car_normal = normalize(mat3(car_inverse) * (mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	float alpha = 0.0;
	vec3 albedo = vec3(0.02);
	float roughness = 0.04;
	vec3 normal_car = car_normal;
	if (wet > 0.01) {
		vec3 drop = car_drops(car_pos, car_normal, car_speed, wet, TIME, drop_cell);
		if (drop.z > 0.01) {
			// Gewölbte Perle: Normale zur Seite gekippt, sonst durchsichtig (nur der Glanz ist zu sehen)
			vec3 side;
			vec3 up;
			surface_axes(car_normal, side, up);
			normal_car = normalize(car_normal + (side * drop.x + up * drop.y) * 0.8);
			alpha = drop.z * 0.55;
		}
	}
	float cover = car_snow(car_pos, car_normal, snow);
	if (cover > 0.0) {
		albedo = mix(albedo, vec3(0.93, 0.95, 0.98), cover);
		alpha = max(alpha, cover);
		roughness = mix(roughness, 0.85, cover);
		normal_car = normalize(mix(normal_car, car_normal, cover));
	}
	if (alpha <= 0.002) {
		discard;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(car_basis * normal_car, 0.0)).xyz);
	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
