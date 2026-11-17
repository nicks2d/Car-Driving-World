// Gemeinsamer Teil der Scheiben des Autos (CarModel): dunkles, leicht spiegelndes Glas. Fenster runter
// (Taste V): Seitenscheiben (Fläche zeigt zur Seite) verschwinden von oben bis zur Brüstungslinie.
// Lage im Auto: car_inverse rechnet Welt- in Auto-Koordinaten (x quer, y hoch, z nach vorne).
// Wetter am Auto (CarWeather): Tropfen, die das Bild dahinter brechen (nur in der Variante mit
// RAIN_DROPS, solange das Auto nass ist), Eis (morgens unter 0 °C, taut beim Fahren von unten her ab)
// und Schnee auf flachen Scheiben. In der Cockpit-Sicht (inside = 1) sind die Scheiben von innen fast klar.
// Eingebunden von car_glass.gdshader (trocken) und car_glass_rain.gdshader (mit Tropfen, RAIN_DROPS).

#include "res://shaders/car_weather.gdshaderinc"

uniform vec4 glass_color : source_color = vec4(0.03, 0.04, 0.05, 0.6);
// 0 = zu, 1 = ganz unten
uniform float window_open = 0.0;
uniform mat4 car_inverse;
// Höhe der Brüstung und der Oberkante der Scheiben im Auto (Meter)
uniform float belt_y = 0.9;
uniform float top_y = 1.3;
// Tempo des Autos (m/s) und Kamera im Auto (0 oder 1)
uniform float car_speed = 0.0;
uniform float inside = 0.0;
// Deckkraft der Scheiben von innen
uniform float inside_opacity = 0.1;
// Wetter am Auto 0–1: nass (Tropfen), Schnee, Eis
uniform float wet = 0.0;
uniform float snow = 0.0;
uniform float frost = 0.0;
// Größe der Tropfen-Zellen in Metern (ein Tropfen pro Zelle)
uniform float drop_cell = 0.022;
#ifdef RAIN_DROPS
// Nur in der Regen-Variante: Das Bild hinter der Scheibe abgreifen kostet eine Kopie des ganzen Bilds
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
#endif

varying vec3 car_pos;
varying vec3 car_normal;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	car_pos = (car_inverse * vec4(world, 1.0)).xyz;
	car_normal = normalize(mat3(car_inverse) * (mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	if (window_open > 0.001 && abs(car_normal.x) > 0.55
			&& car_pos.y > top_y - window_open * (top_y - belt_y + 0.02)) {
		discard;
	}
	float alpha = mix(glass_color.a, inside_opacity, inside);
	vec3 albedo = glass_color.rgb;
	vec3 emission = vec3(0.0);
	float roughness = 0.03;
#ifdef RAIN_DROPS
	if (wet > 0.01) {
		vec3 drop = car_drops(car_pos, car_normal, car_speed, wet, TIME, drop_cell);
		if (drop.z > 0.01) {
			// Das Bild hinter dem Tropfen gebrochen (umgedreht und verschoben) zeigen
			vec3 behind = texture(screen_tex, SCREEN_UV - drop.xy * 0.025).rgb;
			emission = behind * drop.z * 0.9;
			albedo *= 1.0 - drop.z;
			alpha = mix(alpha, 1.0, drop.z * 0.85);
			roughness = 0.0;
		}
	}
#endif
	// Eis: milchig weiß mit Eisblumen, von innen kaum durchsichtig
	float h = clamp((car_pos.y - belt_y) / max(top_y - belt_y, 0.1), 0.0, 1.0);
	float ice = car_frost(car_pos, h, frost);
	if (ice > 0.0) {
		float crystals = weather_noise(car_pos.xy * 90.0 + car_pos.zz * 70.0);
		albedo = mix(albedo, vec3(0.78, 0.84, 0.9) * (0.85 + 0.15 * crystals), ice);
		emission *= 1.0 - ice;
		alpha = mix(alpha, 0.88, ice);
		roughness = mix(roughness, 0.55, ice);
	}
	// Schnee auf flachen Scheiben (Heckscheibe, Glasdach)
	float cover = car_snow(car_pos, car_normal, snow);
	if (cover > 0.0) {
		albedo = mix(albedo, vec3(0.92, 0.94, 0.97), cover);
		emission *= 1.0 - cover;
		alpha = mix(alpha, 1.0, cover);
		roughness = mix(roughness, 0.85, cover);
	}
	ALBEDO = albedo;
	EMISSION = emission;
	ALPHA = alpha;
	METALLIC = 0.2;
	ROUGHNESS = roughness;
}
