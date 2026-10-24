// Glas ohne Unschärfe (für das HUD beim Fahren): dunkel getönt, runde Ecken, feiner Rand.
// Liest das Bild dahinter nicht (keine Bildschirmkopie, die kostet auf dem Mac ~1,7 ms),
// sondern legt sich nur halb durchsichtig darüber. Gleiche Form wie glass.gdshader.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 24.0;
uniform vec4 tint : source_color = vec4(0.055, 0.07, 0.1, 0.66);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.14);

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded_box(p, rect_size * 0.5, radius);
	float aa = max(fwidth(d), 0.001);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	// Oben etwas heller als unten, wie Licht auf Glas
	vec3 color = tint.rgb * mix(1.25, 0.9, UV.y);
	float alpha = tint.a;
	float edge = 1.0 - smoothstep(0.0, aa * 1.5, abs(d + 0.75));
	color = mix(color, border_color.rgb, edge * border_color.a);
	alpha = mix(alpha, 1.0, edge * border_color.a);
	COLOR = vec4(color, alpha * inside * COLOR.a);
}
