// Straßen-Shader: Asphalt mit Mittellinie (gestrichelt) und Randlinien, daneben Schotter.
// UV.x geht quer über die Fahrbahn von 0 (linker Rand) bis 1 (rechter Rand),
// außerhalb davon liegt das Bankett. UV.y ist die Entfernung entlang der Straße in Metern.
// Kreuzungsflächen haben UV2.x = 1: keine Markierungen, Schotter steht in UV2.y.
// Wetter (globale Shader-Werte): Nässe macht den Asphalt dunkel und glatt, in Senken und
// Fahrspuren bilden sich Pfützen, die spiegeln (mit SSR). Schnee bedeckt die Straße
// außer in den Reifenspuren, im Winter liegt er auch auf dem Bankett.
// Im Tunnel (UV2.y = überdacht, nur bei normaler Straße) bleibt die Fahrbahn trocken.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;

// Breite der Fahrbahn in Metern (setzt RoadNetwork beim Start aus seiner road_width)
uniform float road_width = 9.0;
// Größe einer Textur-Kachel in Metern
uniform float asphalt_scale = 3.5;
uniform float gravel_scale = 2.5;
uniform vec3 line_color : source_color = vec3(0.92, 0.92, 0.88);
// Mittellinie: Strich- und Lückenlänge (deutsche Landstraße: 6 m / 12 m)
uniform float dash_length = 6.0;
uniform float dash_gap = 12.0;
uniform float center_line_width = 0.12;
uniform float edge_line_width = 0.15;
// So weit sind die Randlinien vom Fahrbahnrand entfernt
uniform float edge_line_inset = 0.3;

// Wie viel der nassen Straße unter Pfützen liegt (0 bis 1)
uniform float puddle_amount = 0.3;

global uniform float wetness;
global uniform float road_snow;
global uniform float snow_cover;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Weit entfernte Straßen etwas anheben: das grobe ferne Gelände würde sie sonst verschlucken
	float distance = length(world_pos - CAMERA_POSITION_WORLD);
	VERTEX.y += clamp((distance - 250.0) / 900.0, 0.0, 1.0) * 1.2;
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	float across = UV.x * road_width;  // Meter vom linken Fahrbahnrand
	float along = UV.y;                // Meter entlang der Straße
	vec2 uv_a = vec2(across, along) / asphalt_scale;
	float noise = texture(variation_noise, world_pos.xz / 60.0).r;

	// --- Asphalt: etwas dunkler und kühler als das Foto, mit Flecken ---
	vec3 asphalt = texture(asphalt_albedo, uv_a).rgb;
	asphalt = mix(asphalt, vec3(luminance(asphalt)) * vec3(0.95, 0.97, 1.0), 0.6) * mix(0.7, 1.0, noise);
	// Dunklere Fahrspuren, wo die Reifen rollen
	float lane = fract(UV.x * 2.0);
	float wheel_tracks = smoothstep(0.12, 0.0, abs(lane - 0.3)) + smoothstep(0.12, 0.0, abs(lane - 0.72));
	float junction = UV2.x;
	// Kreuzungen haben keine Spuren, sind dafür insgesamt so dunkel wie eine Fahrbahn im Mittel
	asphalt *= 1.0 - mix(wheel_tracks * 0.12, 0.04, junction);

	// --- Markierungen ---
	float aa = fwidth(across) * 0.75;
	float center_distance = abs(across - road_width * 0.5);
	float center = 1.0 - smoothstep(center_line_width * 0.5 - aa, center_line_width * 0.5 + aa, center_distance);
	float dash = step(fract(along / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));
	float edge_distance = min(abs(across - edge_line_inset), abs(across - (road_width - edge_line_inset)));
	float edge = 1.0 - smoothstep(edge_line_width * 0.5 - aa, edge_line_width * 0.5 + aa, edge_distance);
	// Etwas abgefahrene Farbe: nicht überall gleich deckend
	float paint = max(center * dash, edge) * mix(0.75, 1.0, texture(variation_noise, vec2(across, along) / 4.0).r);
	paint *= 1.0 - junction;

	// --- Bankett (Schotter) außerhalb der Fahrbahn ---
	vec3 gravel = texture(gravel_albedo, vec2(across, along) / gravel_scale).rgb;
	gravel = mix(gravel, vec3(luminance(gravel)) * vec3(0.95, 0.93, 0.88) * 1.3, 0.85);
	float shoulder = 1.0 - smoothstep(-0.05, 0.05, min(UV.x, 1.0 - UV.x) * road_width);
	shoulder = mix(shoulder, UV2.y, junction);

	vec3 albedo = mix(asphalt, line_color, paint);
	albedo = mix(albedo, gravel, shoulder);
	float roughness = mix(mix(0.82, 0.6, paint), 0.95, shoulder);
	float normal_depth = mix(mix(0.6, 0.2, paint), 1.0, shoulder);

	// --- Nässe und Pfützen (nicht im Tunnel) ---
	float open_sky = 1.0 - UV2.y * (1.0 - junction);
	float wet = wetness * open_sky;
	float snow_road = road_snow * open_sky;
	float snow_side = snow_cover * open_sky;
	float puddle_noise = texture(variation_noise, world_pos.xz / 9.0).r * 0.75
		+ texture(variation_noise, world_pos.xz / 2.3).r * 0.25 + wheel_tracks * 0.06 * (1.0 - junction);
	float puddle = smoothstep(1.0 - puddle_amount - 0.04, 1.0 - puddle_amount + 0.04, puddle_noise)
		* smoothstep(0.35, 0.9, wet) * (1.0 - shoulder);
	albedo *= 1.0 - wet * mix(0.45, 0.3, shoulder);
	roughness = mix(roughness, mix(0.22, 0.6, shoulder), wet);
	albedo *= 1.0 - puddle * 0.3;
	roughness = mix(roughness, 0.02, puddle);
	normal_depth *= 1.0 - puddle * 0.95;

	// --- Schnee: auf der Fahrbahn außer in den Reifenspuren, im Winter auf dem Bankett ---
	float snow_noise = texture(variation_noise, vec2(across, along) / 3.0).r;
	float tracks_clear = wheel_tracks * (1.0 - junction) * smoothstep(0.95, 0.6, snow_road);
	float snow = clamp(snow_road * 1.3 - tracks_clear * 1.2 - (1.0 - snow_road) * snow_noise, 0.0, 1.0);
	snow = max(snow * (1.0 - shoulder), shoulder * smoothstep(0.2, 0.6, max(snow_side, snow_road) + snow_noise * 0.3 - 0.15));
	albedo = mix(albedo, vec3(0.78, 0.8, 0.84) * mix(0.85, 1.0, snow_noise), snow);
	roughness = mix(roughness, 0.6, snow);

	vec4 n_asphalt = texture(asphalt_normal, uv_a);
	vec4 n_gravel = texture(gravel_normal, vec2(across, along) / gravel_scale);
	NORMAL_MAP = mix(n_asphalt, n_gravel, shoulder).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - snow * 0.7);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = mix(0.4, 0.5, wet);
}
