// Fallendes Wasser (Wasserfälle, Überlauf der Staumauer): Streifen aus Schaum, die nach unten
// laufen. UV.x quer (0–1), UV.y entlang des Falls in Metern (nach unten zunehmend).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.45, 0.58, 0.62);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.97);
// Fallgeschwindigkeit (Meter pro Sekunde in UV.y) und Feinheit der Streifen
uniform float speed = 3.0;
uniform float streaks = 9.0;
// Ränder links und rechts weich ausblenden (natürliche Fälle; die Staumauer hat Wände)
uniform bool soft_edges = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float t = TIME * speed;
	// Längliche Streifen: quer fein, längs grob, laufen nach unten
	float a = value_noise(vec2(UV.x * streaks, UV.y * 0.18 - t * 0.18));
	float b = value_noise(vec2(UV.x * streaks * 2.3 + 5.7, UV.y * 0.45 - t * 0.45));
	float c = value_noise(vec2(UV.x * streaks * 5.1 + 1.3, UV.y * 1.1 - t * 1.05));
	float foam = smoothstep(0.38, 0.9, a * 0.5 + b * 0.35 + c * 0.25);
	float edge = 1.0;
	if (soft_edges) {
		edge = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.82, 1.0, UV.x));
		// Die Ränder sind ausgefranst (nicht gerade)
		edge *= smoothstep(0.15, 0.5, value_noise(vec2(UV.x * 3.0, UV.y * 0.3 - t * 0.3)) + edge * 0.6);
	}
	ALBEDO = mix(water_color, foam_color, foam);
	ROUGHNESS = mix(0.08, 0.45, foam);
	SPECULAR = 0.5;
	EMISSION = foam_color * foam * 0.04;
	// Ganz durchsichtig wird es nicht (sonst sieht man die Felsen „trocken“ durch)
	if (edge < 0.35 + hash(floor(FRAGCOORD.xy)) * 0.3) {
		discard;
	}
}
