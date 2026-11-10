// Scheiben des Autos (CarModel): dunkles, leicht spiegelndes Glas. Fenster runter (Taste V):
// Seitenscheiben (Fläche zeigt zur Seite) verschwinden von oben bis zur Brüstungslinie.
// Lage im Auto: car_inverse rechnet Welt- in Auto-Koordinaten (x quer, y hoch, z nach vorne).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 glass_color : source_color = vec4(0.03, 0.04, 0.05, 0.6);
// 0 = zu, 1 = ganz unten
uniform float window_open = 0.0;
uniform mat4 car_inverse;
// Höhe der Brüstung und der Oberkante der Scheiben im Auto (Meter)
uniform float belt_y = 0.9;
uniform float top_y = 1.3;

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
	ALBEDO = glass_color.rgb;
	ALPHA = glass_color.a;
	METALLIC = 0.2;
	ROUGHNESS = 0.03;
}
