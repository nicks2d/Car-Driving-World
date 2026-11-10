// Verkehrszeichen (traffic_signs.gd): Farben aus den Punktfarben (schon linear), die Fläche
// reflektiert wie die Leitpfosten: Licht von der Kamera (Scheinwerfer) kommt hell zurück.
// Statt des (blauen) Himmelslichts gibt es ein neutrales Grundlicht aus der Farbe von Sonne bzw.
// Mond: sonst sind weiße Schilder im Schatten knallblau.
shader_type spatial;
render_mode cull_back, ambient_light_disabled;

// Wie stark das zurückgeworfene Scheinwerferlicht ist
uniform float retro_strength = 5.0;
// Grundlicht im Schatten (Anteil des Sonnenlichts)
uniform float fill_strength = 0.4;

void fragment() {
	ALBEDO = COLOR.rgb;
	// Matt: sonst spiegelt die Fläche den blauen Himmel
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
}

void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0);
	float back = pow(max(dot(LIGHT, VIEW), 0.0), 16.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (diffuse + back * retro_strength) / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * fill_strength / PI;
	}
}
