// Milchglas für HUD und Menüs: das Bild dahinter weichgezeichnet, dunkel getönt,
// mit runden Ecken und einem feinen hellen Rand.
// Godot kopiert das Bild dahinter einmal pro Bild (ohne Mipmaps, die wären teuer).
// Die Unschärfe: 9 Stichproben auf zwei Ringen (ca. 18 Punkte Radius). Kostet nur dort,
// wo Glas ist.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
// Größe der Fläche (setzt GlassPanel) und Eckenradius, beides in UI-Einheiten
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 24.0;
uniform vec4 tint : source_color = vec4(0.055, 0.07, 0.1, 0.48);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.14);
// 0 = keine Unschärfe (nur getönt), 1 = volle Unschärfe
uniform float blur = 1.0;
// Radius der Unschärfe in Bildschirmpunkten
uniform float blur_radius = 30.0;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded_box(p, rect_size * 0.5, radius);
	float aa = max(fwidth(d), 0.001);
	float inside = 1.0 - smoothstep(-aa, aa, d);

	vec3 back = vec3(0.0);
	if (blur > 0.0) {
		// 8 Stichproben auf einem Ring plus Mitte; jede liest dank linearer Filterung schon
		// 4 Bildpunkte gemittelt. Abwechselnd pro Bildpunkt um 22,5° gedreht (gegen Muster).
		float turn = mod(FRAGCOORD.x + FRAGCOORD.y, 2.0) * 0.3926991;
		back = textureLod(screen_texture, SCREEN_UV, 0.0).rgb * 0.2;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7853982 + turn;
			float r = blur_radius * blur * (i % 2 == 0 ? 1.0 : 0.55);
			vec2 offset = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
			back += textureLod(screen_texture, SCREEN_UV + offset, 0.0).rgb * 0.1;
		}
	} else {
		back = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	}
	vec3 color = mix(back, tint.rgb, tint.a);
	// 1 Punkt breiter Rand an der Innenkante
	float edge = 1.0 - smoothstep(0.0, aa * 1.5, abs(d + 0.75));
	color = mix(color, border_color.rgb, edge * border_color.a);
	COLOR = vec4(color, inside * COLOR.a);
}
