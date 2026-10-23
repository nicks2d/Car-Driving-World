// Talnebel: eine Nebelschicht, die unten am Talboden dicht ist und nach oben dünner wird.
// Ein Viereck vor der Kamera deckt den ganzen Bildschirm ab. Für jeden Bildpunkt wird aus
// dem Tiefenpuffer die Weltposition berechnet und ausgerechnet, wie viel Nebel auf dem
// Weg von der Kamera dorthin liegt (Dichte nimmt mit der Höhe exponentiell ab, das lässt
// sich genau ausrechnen). So ist nahes Zeug kaum vernebelt, ferne Talböden ganz.
// Godots eingebauter Höhennebel kann das nicht: der hängt nur von der Höhe ab, nicht vom Abstand.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Talboden (Welt-Höhe in Metern), Dichte dort (pro Meter) und Dicke der Schicht (Meter)
uniform float floor_height = 100.0;
uniform float density = 0.01;
uniform float thickness = 30.0;
uniform vec3 fog_color : source_color = vec3(0.8, 0.82, 0.85);
// Sonne scheint durch den Nebel (heller Schein in Sonnenrichtung)
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color = vec3(0.0);
// Weiter als so viele Meter wird nicht gerechnet (Himmel)
uniform float max_distance = 6000.0;

void vertex() {
	// Das Viereck (-1 bis 1) direkt auf den Bildschirm legen
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	vec3 ray = world - camera;
	float dist = min(length(ray), max_distance);
	vec3 dir = normalize(ray);

	// Höhe über dem Talboden am Anfang und Ende des Wegs (unter dem Boden nicht dichter werden)
	float b = 1.0 / thickness;
	float y0 = max(camera.y - floor_height, -10.0);
	float y1 = max(y0 + dir.y * dist, -10.0);
	// Integral der Dichte entlang des Wegs: density * exp(-b * y)
	float amount;
	if (abs(y1 - y0) < 0.5) {
		amount = density * exp(-b * y0) * dist;
	} else {
		amount = density * dist * (exp(-b * y0) - exp(-b * y1)) / (b * (y1 - y0));
	}
	float fog = 1.0 - exp(-amount);

	float sun = pow(max(dot(dir, sun_direction), 0.0), 8.0);
	ALBEDO = fog_color + sun_color * sun;
	ALPHA = clamp(fog, 0.0, 0.985);
}
