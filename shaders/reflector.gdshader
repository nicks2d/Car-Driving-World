// Rückstrahler (Leitpfosten): wirft Licht genau dorthin zurück, wo es herkommt.
// Scheinwerfer sitzen fast an der Kamera, deshalb leuchten die Rückstrahler nachts hell auf,
// sobald das eigene Licht sie trifft. Tagsüber sind sie nur ein heller Fleck.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.92, 0.8);
// Wie stark das zurückgeworfene Licht ist
uniform float retro_strength = 40.0;

void fragment() {
	ALBEDO = color * 0.4;
	ROUGHNESS = 0.6;
}

void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0);
	// Licht von der Kamera aus (LIGHT fast gleich VIEW) kommt stark zurück
	float back = pow(max(dot(LIGHT, VIEW), 0.0), 24.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (diffuse + back * retro_strength) / PI;
}
