// Schachbrett-Boden mit Gitterlinien, damit man beim Fahren die Bewegung sieht.
// Das Muster wird aus der Welt-Position berechnet, daher braucht es keine Textur.
shader_type spatial;

// Die zwei Farben des Schachbretts
uniform vec3 color_a : source_color = vec3(0.30, 0.32, 0.34);
uniform vec3 color_b : source_color = vec3(0.22, 0.24, 0.26);
// Farbe der Gitterlinien
uniform vec3 line_color : source_color = vec3(0.75, 0.75, 0.72);
// Größe eines Feldes in Metern
uniform float tile_size = 4.0;
// Breite der Linien (in Bildschirm-Pixeln)
uniform float line_width = 1.0;

varying vec3 world_pos;

void vertex() {
	// Position des Punktes in der Welt merken (nicht relativ zum Mesh)
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / tile_size;

	// Schachbrett: abwechselnd Farbe A und B
	vec2 cell = floor(coord);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(color_a, color_b, checker);

	// fwidth = wie viele Felder ein Pixel abdeckt. In der Ferne ist das viel,
	// dann blenden wir das Muster aus, sonst flimmert es.
	vec2 pixel_size = fwidth(coord);
	float fade = clamp(max(pixel_size.x, pixel_size.y) * 2.0, 0.0, 1.0);
	col = mix(col, (color_a + color_b) * 0.5, fade);

	// Gitterlinien an den Feldkanten, immer etwa gleich dick auf dem Bildschirm
	vec2 dist_to_line = abs(fract(coord - 0.5) - 0.5) / pixel_size;
	float line = 1.0 - clamp(min(dist_to_line.x, dist_to_line.y) - line_width + 1.0, 0.0, 1.0);
	col = mix(col, line_color, line * 0.5 * (1.0 - fade));

	ALBEDO = col;
	ROUGHNESS = 0.9;
}
