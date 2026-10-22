// Wasser-Shader für Seen und Flüsse.
// - Wellen: zwei Normal-Maps, die gegeneinander verschoben werden (bei Flüssen in Fließrichtung)
// - Spiegelung: kommt automatisch vom Himmel, weil das Wasser sehr glatt ist (geringe Rauheit)
// - Tiefe: aus dem Tiefenpuffer. Flaches Wasser ist durchsichtig und hell, tiefes dunkel.
// - Schaum: ein heller Rand, wo das Wasser auf das Ufer trifft
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wave_normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.16, 0.30, 0.28);
uniform vec3 deep_color : source_color = vec3(0.015, 0.05, 0.07);
uniform vec3 foam_color : source_color = vec3(0.85, 0.88, 0.9);
// Ab dieser Wassertiefe (Meter entlang des Blicks) ist das Wasser ganz dunkel
uniform float deep_distance = 5.0;
// Breite des Schaumrands in Metern
uniform float foam_width = 0.35;
// Größe der Wellen (Meter pro Textur-Kachel) und wie stark sie das Licht ablenken
uniform float wave_scale = 12.0;
uniform float wave_strength = 0.5;
// Fließgeschwindigkeit von Flüssen (Meter pro Sekunde)
uniform float flow_speed = 1.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// --- Wellen ---
	vec2 flow = UV;  // Fließrichtung bei Flüssen, (0, 0) bei Seen
	vec2 base = world_pos.xz / wave_scale;
	vec2 drift = flow * TIME * flow_speed / wave_scale;
	vec3 n1 = texture(wave_normal_a, base + drift + vec2(TIME * 0.011, TIME * 0.006)).rgb;
	vec3 n2 = texture(wave_normal_b, base * 1.9 + drift * 1.4 - vec2(TIME * 0.008, -TIME * 0.010)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = wave_strength;

	// --- Wie viel Wasser liegt zwischen Oberfläche und Boden dahinter? ---
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(-behind.z - (-VERTEX.z), 0.0);
	float deep = clamp(thickness / deep_distance, 0.0, 1.0);

	// --- Schaum am Ufer, mit etwas Bewegung ---
	float foam_noise = texture(wave_normal_a, base * 3.0 + vec2(TIME * 0.03, 0.0)).r;
	float foam = (1.0 - smoothstep(0.0, foam_width * (0.6 + foam_noise * 0.8), thickness)) * 0.45;

	vec3 color = mix(shallow_color, deep_color, sqrt(deep));
	ALBEDO = mix(color, foam_color, foam);
	ALPHA = clamp(mix(0.45, 0.97, deep) + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.6;
}
