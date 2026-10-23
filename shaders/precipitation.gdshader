// Aussehen der Regentropfen und Schneeflocken.
// Regen: dünne Striche entlang der Bewegung relativ zur Kamera (fährt man schnell, kommen
// sie schräg entgegen). Schnee: weiche runde Flocken, die immer zur Kamera zeigen.
// Nur ein Teil der Partikel ist sichtbar: je stärker der Niederschlag, desto mehr.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform bool is_snow = false;
// Anteil der sichtbaren Partikel (0 bis 1)
uniform float intensity = 1.0;
// Regen: Richtung und Länge der Striche
uniform vec3 streak_direction = vec3(0.0, -1.0, 0.0);
uniform float streak_length = 0.5;
// Breite der Regenstriche bzw. Größe der Flocken (Meter)
uniform float size = 0.012;
uniform vec3 color : source_color = vec3(0.75, 0.78, 0.82);
uniform float opacity = 0.3;
uniform float brightness = 1.0;
// Am Rand des Kastens ausblenden (halbe Kastenbreite)
uniform float fade_radius = 18.0;

varying float fade;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_camera = CAMERA_POSITION_WORLD - center;
	float d = length(to_camera);
	float visible = step(INSTANCE_CUSTOM.x, intensity);
	vec3 offset;
	if (is_snow) {
		float flake = size * mix(0.6, 1.4, INSTANCE_CUSTOM.y);
		offset = (INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5) + INV_VIEW_MATRIX[1].xyz * (0.5 - UV.y)) * flake;
	} else {
		// Ferne Striche etwas breiter, sonst flimmern sie (dünner als ein Bildpunkt)
		vec3 right = normalize(cross(streak_direction, to_camera));
		offset = right * (UV.x - 0.5) * size * (1.0 + d * 0.12) + streak_direction * (UV.y - 0.5) * streak_length;
	}
	VERTEX = center + offset * visible;
	// Nicht direkt vor der Linse und nicht hart am Kastenrand
	float edge = max(abs(to_camera.x), abs(to_camera.z));
	fade = (1.0 - smoothstep(fade_radius * 0.7, fade_radius, edge)) * smoothstep(0.6, 2.0, d)
		/ (1.0 + d * 0.04);
}

void fragment() {
	float alpha;
	if (is_snow) {
		float r = length(UV - 0.5) * 2.0;
		alpha = 1.0 - smoothstep(0.3, 1.0, r);
	} else {
		float across = abs(UV.x - 0.5) * 2.0;
		float along = abs(UV.y - 0.5) * 2.0;
		alpha = (1.0 - across * across) * (1.0 - along * along);
	}
	ALBEDO = color * brightness;
	ALPHA = alpha * opacity * fade;
}
