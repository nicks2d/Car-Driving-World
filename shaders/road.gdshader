// Straßen-Shader: Asphalt mit Mittellinie (gestrichelt) und Randlinien, daneben Schotter.
// UV.x geht quer über die Fahrbahn von 0 (linker Rand) bis 1 (rechter Rand),
// außerhalb davon liegt das Bankett. UV.y ist die Entfernung entlang der Straße in Metern.
// Kreuzungsflächen haben UV2.x = 1: keine Markierungen, Schotter steht in UV2.y.
// Wetter (globale Shader-Werte): Nässe macht den Asphalt dunkel und glatt, in Senken und
// Fahrspuren bilden sich Pfützen, die spiegeln (mit SSR). Schnee bedeckt die Straße
// außer in den Reifenspuren, im Winter liegt er auch auf dem Bankett.
// Im Tunnel (UV2.y = überdacht, nur bei normaler Straße) bleibt die Fahrbahn trocken.
// lane_profile: 0 = Landstraße (Mittellinie gestrichelt), 1 = Autobahn (je Richtung zwei
// Fahrstreifen, Standstreifen, Mittelstreifen), 2 = Rampe (nur Randlinien).
// Straßenrand: Das Bankett geht mit einer weichen, unregelmäßigen Kante in Gras über (wie das Gelände),
// in den Fahrspuren dunklere, glattere Reifenspuren, ab und zu Flickstellen (frischer, dunkler Asphalt mit
// Fugen).
// Autobahn mit Zusatzfahrstreifen (Verzögerungs-/Beschleunigungsstreifen): Die Punktfarbe sagt,
// wie viel breiter die Fahrbahn links/rechts ist (COLOR.r/g × 10 m, UV.x reicht dann über 0 bzw.
// 1 hinaus) und welche Markierung dort gilt (COLOR.b/a × 3): 1 = Blockmarkierung zum
// Zusatzstreifen, 2 = Sperrfläche, 3 = Verziehung (schraffiert, mit Blockmarkierung).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;
// Gras am Bankett (gleiche Textur und Farbe wie im Gelände, setzt RoadNetwork beim Start)
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_color : source_color = vec3(0.27, 0.45, 0.10);
uniform float grass_scale = 4.0;
// Breite des Banketts (Meter) und wo darin das Gras im Mittel anfängt (Anteil)
uniform float shoulder_width = 1.5;
uniform float grass_start = 0.55;
// Flickstellen: so viele Meter Abstand im Mittel, Anteil der Abschnitte mit einer Flickstelle
uniform float patch_spacing = 37.0;
uniform float patch_share = 0.3;

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
// So weit sind die Randlinien vom Fahrbahnrand entfernt (Rampen: rechts weiter, siehe unten)
uniform float edge_line_inset = 0.3;
// Rampe: Abstand der rechten Randlinie (links 0,75 m, rechts 1,25 m, Fahrstreifen 4,5 m);
// negativ = wie links
uniform float edge_line_inset_right = -1.0;
// Zusatzfahrstreifen der Autobahn: so weit liegt seine Randlinie innen vom Fahrbahnrand
uniform float aux_edge_inset = 1.25;
uniform int lane_profile = 0;
// Autobahn (je Seite von außen nach innen): Standstreifen, zwei Fahrstreifen, innerer Rand,
// dahinter der Mittelstreifen. Die Linien sind 30 cm (außen) bzw. 15 cm breit.
uniform float hw_shoulder = 2.5;
uniform float hw_lane = 3.75;
uniform float hw_inner = 0.75;

// Wie viel der nassen Straße unter Pfützen liegt (0 bis 1)
uniform float puddle_amount = 0.3;

global uniform float wetness;
global uniform float road_snow;
global uniform float snow_cover;
global uniform float season_spring;
global uniform float season_autumn;
global uniform float season_winter;
#include "res://shaders/cloud_shadow.gdshaderinc"

varying vec3 world_pos;
// Zusatzbreite und Markierung je Seite (nur Autobahn, siehe oben)
varying vec4 aux;
// Landstraße: Senke im Höhenprofil (Punktfarbe Rot, 0–1): dort stehen mehr Pfützen
varying float sag;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Andere Straßen haben keine Punktfarbe (dann wäre sie weiß)
	aux = lane_profile == 1 ? COLOR : vec4(0.0);
	// Kreuzungen und Parkbuchten (UV2.x = 1) haben keine Punktfarbe (dort wäre sie weiß)
	sag = lane_profile == 0 ? COLOR.r * (1.0 - UV2.x) : 0.0;
	// Weit entfernte Straßen etwas anheben: das grobe ferne Gelände würde sie sonst verschlucken
	float distance = length(world_pos - CAMERA_POSITION_WORLD);
	VERTEX.y += clamp((distance - 250.0) / 900.0, 0.0, 1.0) * 1.2;
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash1(float x) {
	return fract(sin(x * 127.1 + 11.7) * 43758.5453);
}

// Flickstelle an dieser Stelle? 1 = darin, 2 = auf der Fuge am Rand, 0 = nein. across in Metern vom linken
// Rand, Fahrbahnbreite width
float patch_at(float across, float along, float width) {
	float cell = floor(along / patch_spacing);
	float h1 = hash1(cell);
	if (h1 > patch_share) {
		return 0.0;
	}
	float h2 = hash1(cell + 17.3);
	float h3 = hash1(cell + 41.9);
	float len = mix(3.0, 12.0, h2);
	float start = cell * patch_spacing + hash1(cell + 5.1) * (patch_spacing - len);
	// Quer: eine Fahrbahnhälfte, nicht ganz bis zum Rand
	float left = h3 < 0.5 ? 0.25 : width * 0.5 + 0.05;
	float right = left + width * mix(0.3, 0.48, hash1(cell + 2.3));
	float u = along - start;
	if (u < 0.0 || u > len || across < left || across > right) {
		return 0.0;
	}
	float edge = min(min(u, len - u), min(across - left, right - across));
	return edge < 0.05 ? 2.0 : 1.0;
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
	// Abstand zum näheren Außenrand (Autobahn ist spiegelgleich); im Zusatzstreifen negativ
	float side = min(across, road_width - across);
	bool right_half = across > road_width * 0.5;
	float extra = right_half ? aux.g * 10.0 : aux.r * 10.0;
	float mark = floor((right_half ? aux.a : aux.b) * 3.0 + 0.5);
	if (lane_profile == 1) {
		float lane_1 = hw_shoulder + hw_lane * 0.5;
		float lane_2 = hw_shoulder + hw_lane * 1.5;
		wheel_tracks = 0.0;
		for (int k = 0; k < 2; k++) {
			float c = k == 0 ? lane_1 : lane_2;
			wheel_tracks += smoothstep(0.5, 0.0, abs(side - c + 0.9)) + smoothstep(0.5, 0.0, abs(side - c - 0.9));
		}
	} else if (lane_profile == 2) {
		// Mitte des Fahrstreifens zwischen den beiden Randlinien
		float inset_r = edge_line_inset_right < 0.0 ? edge_line_inset : edge_line_inset_right;
		float lane_mid = (edge_line_inset + road_width - inset_r) * 0.5;
		wheel_tracks = smoothstep(0.5, 0.0, abs(across - lane_mid + 0.9))
			+ smoothstep(0.5, 0.0, abs(across - lane_mid - 0.9));
	} else if (lane_profile == 3) {
		// Parkplatz: Fahrspuren nur in der Fahrgasse am autobahnseitigen Rand
		wheel_tracks = smoothstep(0.5, 0.0, abs(across - 3.1)) + smoothstep(0.5, 0.0, abs(across - 4.9));
	}
	float junction = UV2.x;
	// Reifenspuren: dunkler und etwas glatter, mit Unterschieden entlang der Straße
	float track_strength = wheel_tracks * mix(0.7, 1.15, texture(variation_noise, vec2(across * 0.2, along / 30.0)).r);
	// Kreuzungen haben keine Spuren, sind dafür insgesamt so dunkel wie eine Fahrbahn im Mittel
	asphalt *= 1.0 - mix(track_strength * 0.2, 0.04, junction);
	// Flickstellen: frischer, dunklerer Asphalt mit Fuge (nicht auf Kreuzungen und Parkplätzen)
	float patch = (lane_profile == 3 || junction > 0.5) ? 0.0 : patch_at(across, along, road_width);
	if (patch > 1.5) {
		asphalt *= 0.45;
	} else if (patch > 0.5) {
		asphalt = mix(asphalt, vec3(luminance(asphalt)) * 0.62, 0.8);
	}

	// --- Markierungen ---
	float aa = fwidth(across) * 0.75;
	float center_distance = abs(across - road_width * 0.5);
	float center = 1.0 - smoothstep(center_line_width * 0.5 - aa, center_line_width * 0.5 + aa, center_distance);
	float dash = step(fract(along / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));
	float inset_right = edge_line_inset_right < 0.0 ? edge_line_inset : edge_line_inset_right;
	float edge_distance = min(abs(across - edge_line_inset), abs(across - (road_width - inset_right)));
	float edge = 1.0 - smoothstep(edge_line_width * 0.5 - aa, edge_line_width * 0.5 + aa, edge_distance);
	if (lane_profile == 1) {
		// Autobahn: Randlinie (breit), gestrichelte Linie zwischen den Fahrstreifen, innere Linie
		float edge_line = 1.0 - smoothstep(0.15 - aa, 0.15 + aa, abs(side - hw_shoulder));
		float lane_line = 1.0 - smoothstep(0.075 - aa, 0.075 + aa, abs(side - hw_shoulder - hw_lane));
		float inner_line = 1.0 - smoothstep(0.075 - aa, 0.075 + aa, abs(side - hw_shoulder - hw_lane * 2.0));
		// Zusatzfahrstreifen: Blockmarkierung (Breitstrich 6 m, Lücke 6 m) statt der Randlinie,
		// eigene Randlinie außen; Sperrfläche/Verziehung schräg schraffiert (Streifen 0,5 m)
		float outside = 1.0 - step(hw_shoulder, side);
		if (mark == 1.0 || mark == 3.0) {
			edge_line *= step(fract(along / 12.0), 0.5);
			if (mark == 1.0 && extra > aux_edge_inset + 0.2) {
				edge_line = max(edge_line, 1.0 - smoothstep(0.125 - aa, 0.125 + aa, abs(side + extra - aux_edge_inset)));
			}
		}
		if (mark >= 2.0) {
			float stripes = 1.0 - smoothstep(0.25 - aa, 0.25 + aa, abs(fract((along + side) / 4.0) - 0.5) * 4.0);
			edge_line = max(edge_line, stripes * outside * step(-extra + 0.3, side) * step(side, hw_shoulder - 0.15));
		}
		center = 0.0;
		edge = max(edge_line, inner_line);
		center = lane_line;
	} else if (lane_profile == 2) {
		center = 0.0;
	} else if (lane_profile == 3) {
		// Parkplatz: Markierungen, Inseln und Gehwege baut road_network.gd als Geometrie
		center = 0.0;
		edge = 0.0;
	}
	// Etwas abgefahrene Farbe: nicht überall gleich deckend
	float paint = max(center * dash, edge) * mix(0.75, 1.0, texture(variation_noise, vec2(across, along) / 4.0).r);
	paint *= 1.0 - junction;

	// --- Bankett (Schotter) außerhalb der Fahrbahn ---
	vec3 gravel = texture(gravel_albedo, vec2(across, along) / gravel_scale).rgb;
	gravel = mix(gravel, vec3(luminance(gravel)) * vec3(0.95, 0.93, 0.88) * 1.3, 0.85);
	float shoulder = 1.0 - smoothstep(-0.05, 0.05, min(UV.x * road_width + aux.r * 10.0,
		(1.0 - UV.x) * road_width + aux.g * 10.0));
	shoulder = mix(shoulder, UV2.y, junction);
	// Mittelstreifen der Autobahn: Schotter wie das Bankett
	if (lane_profile == 1) {
		shoulder = max(shoulder, smoothstep(-0.05, 0.05, side - hw_shoulder - hw_lane * 2.0 - hw_inner));
	}

	// Gras am äußeren Rand des Banketts: weiche, unregelmäßige Kante (nicht auf Kreuzungen und Parkplätzen,
	// nicht im Mittelstreifen: dort ist „outside“ 0)
	float outside = max(max(-UV.x * road_width - aux.r * 10.0, (UV.x - 1.0) * road_width - aux.g * 10.0), 0.0);
	float wobble = texture(variation_noise, vec2(along / 23.0, 0.37)).r * 0.6 + texture(variation_noise, vec2(along / 4.1, 0.71)).r * 0.4;
	float grass_edge = shoulder_width * (grass_start + (wobble - 0.5) * 0.7);
	float grass = smoothstep(grass_edge - 0.25, grass_edge + 0.25, outside) * (1.0 - junction);
	if (lane_profile == 3) {
		grass = 0.0;
	}
	vec3 green = mix(grass_color, vec3(0.30, 0.56, 0.10), season_spring * 0.7);
	green = mix(green, vec3(0.42, 0.40, 0.15), season_autumn * 0.45 + season_winter * 0.5);
	vec3 grass_tex = texture(grass_albedo, world_pos.xz / grass_scale).rgb;
	vec3 grass_color_now = mix(grass_tex, luminance(grass_tex) * green * 3.2, 0.85) * mix(0.85, 1.1, noise);

	vec3 albedo = mix(asphalt, line_color, paint);
	albedo = mix(albedo, gravel, shoulder);
	albedo = mix(albedo, grass_color_now, grass * shoulder);
	float roughness = mix(mix(0.82, 0.6, paint), 0.95, shoulder);
	roughness = mix(roughness, 0.75, track_strength * 0.5 * (1.0 - shoulder) * (1.0 - junction));
	if (patch > 0.5) {
		roughness = 0.62;
	}
	float normal_depth = mix(mix(0.6, 0.2, paint), 1.0, shoulder);

	// --- Nässe und Pfützen (nicht im Tunnel) ---
	float open_sky = 1.0 - UV2.y * (1.0 - junction);
	float wet = wetness * open_sky;
	float snow_road = road_snow * open_sky;
	float snow_side = snow_cover * open_sky;
	float puddle_noise = texture(variation_noise, world_pos.xz / 9.0).r * 0.75
		+ texture(variation_noise, world_pos.xz / 2.3).r * 0.25 + wheel_tracks * 0.06 * (1.0 - junction);
	// Auf Landstraßen vor allem in Senken (wenige auf geraden Stücken)
	float amount = lane_profile == 0 ? puddle_amount * 0.4 + sag * 0.5 : puddle_amount;
	float puddle = smoothstep(1.0 - amount - 0.04, 1.0 - amount + 0.04, puddle_noise)
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
	// Wolkenschatten wie im Gelände (nicht im Tunnel)
	albedo *= 1.0 - cloud_shade(world_pos.xz) * 0.5 * open_sky;
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = mix(0.4, 0.5, wet);
}
