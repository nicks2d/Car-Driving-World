// Gelände-Shader: mischt Gras, Waldboden, Fels und Schnee je nach Steigung und Höhe.
// Texturen werden über die Welt-Position gelegt (keine UVs nötig).
// Fels wird „triplanar“ von drei Seiten projiziert, damit steile Hänge nicht verzerrt sind.
// Die Normal-Maps werden selbst in Welt-Koordinaten verrechnet und dann an Godot übergeben.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Großflächiges Rauschen für Farbflecken und gegen sichtbare Kachel-Wiederholung
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;

// Größe einer Textur-Kachel in Metern
uniform float grass_scale = 4.0;
uniform float dirt_scale = 4.0;
uniform float rock_scale = 10.0;
uniform float snow_scale = 6.0;

// Farbkorrektur: die Fotos sind recht bräunlich, wir wollen sattes Grün und grauen Fels
uniform vec3 grass_color : source_color = vec3(0.27, 0.45, 0.10);
uniform float grass_recolor : hint_range(0.0, 1.0) = 0.85;
uniform vec3 dry_grass_color : source_color = vec3(0.50, 0.50, 0.22);
uniform vec3 rock_color : source_color = vec3(0.60, 0.58, 0.55);
uniform float rock_recolor : hint_range(0.0, 1.0) = 0.7;
uniform vec3 alpine_color : source_color = vec3(0.42, 0.40, 0.30);

// Steigung (1 - Normale.y), ab der Fels erscheint bzw. komplett Fels ist
uniform float rock_slope_start = 0.16;
uniform float rock_slope_end = 0.28;
// Schnee ab der Schneefallgrenze (globaler Wert vom Wetter, je nach Jahreszeit; mit Zufall),
// weicher Übergang über snow_blend Meter
uniform float snow_blend = 120.0;
uniform float tree_line = 800.0;

// Horizont-Ring: ohne Detail-Texturen. Wo schon Gelände-Kacheln liegen (chunk_mask, eine
// kleine Karte vom TerrainManager: 1 = Kachel da), versinkt er darunter.
uniform bool far_mode = false;
uniform bool sink_into_chunks = false;
uniform sampler2D chunk_mask : filter_nearest;
uniform vec2 mask_origin = vec2(0.0);
uniform float mask_size = 1.0;

// Wetter und Jahreszeit (globale Shader-Werte, setzt weather.gd)
global uniform float wetness;
global uniform float snow_cover;
global uniform float snow_line;
global uniform float season_spring;
global uniform float season_autumn;
global uniform float season_winter;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (sink_into_chunks) {
		// Ring-Teile unter fertigen Kacheln weit nach unten schieben, sonst nur ein Stück
		vec2 uv = (world_pos.xz - mask_origin) / mask_size;
		float loaded = 0.0;
		if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			loaded = textureLod(chunk_mask, uv, 0.0).r;
		}
		float sink = loaded * 120.0 + 4.0;
		VERTEX.y -= sink;
		world_pos.y -= sink;
	}
}

vec3 unpack_normal(vec4 t) {
	vec2 xy = t.rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// Normal-Map von oben projiziert (für Gras, Erde, Schnee), Ergebnis in Welt-Koordinaten
vec3 top_normal(sampler2D tex, vec2 uv, vec3 n) {
	vec3 t = unpack_normal(texture(tex, uv));
	return normalize(vec3(t.x + n.x, abs(t.z) * n.y, t.y + n.z));
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Durchschnittsfarben der Texturen (linear). Damit sehen weit entferntes Gelände und
// der Horizont-Ring genauso aus wie die Texturen aus der Nähe.
const vec3 GRASS_MEAN = vec3(0.319, 0.236, 0.106);
const vec3 DIRT_MEAN = vec3(0.292, 0.248, 0.120);
const vec3 ROCK_MEAN = vec3(0.121, 0.062, 0.032);
const vec3 SNOW_MEAN = vec3(0.379, 0.379, 0.389);

// Farbkorrektur der Schichten (für Textur-Farbe und Durchschnittsfarbe gleich)
vec3 grade_grass(vec3 c, vec3 green, float variation) {
	return mix(c, luminance(c) * green * 3.2, grass_recolor) * mix(0.85, 1.1, variation);
}
vec3 grade_dirt(vec3 c) {
	return mix(c, luminance(c) * vec3(0.42, 0.40, 0.24) * 2.2, 0.35);
}
vec3 grade_rock(vec3 c, float variation) {
	return mix(c, luminance(c) * rock_color * 4.0, rock_recolor) * mix(0.8, 1.15, variation);
}
vec3 grade_snow(vec3 c) {
	return c * 1.9;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - n.y;
	float big_noise = texture(variation_noise, world_pos.xz / 900.0).r;
	float mid_noise = texture(variation_noise, world_pos.xz / 120.0).r;
	float small_noise = texture(variation_noise, world_pos.xz / 23.0).r;
	float distance_to_camera = length(world_pos - CAMERA_POSITION_WORLD);
	// 0 = nah (Texturen), 1 = fern (nur Durchschnittsfarben)
	float far_blend = far_mode ? 1.0 : smoothstep(700.0, 1500.0, distance_to_camera);

	// --- Gewichte der Schichten ---
	float forest = COLOR.r;
	float rock_w = smoothstep(rock_slope_start, rock_slope_end, slope + (mid_noise - 0.5) * 0.1);
	float line = snow_line + (big_noise - 0.5) * 300.0;
	float snow_w = smoothstep(line - snow_blend, line + snow_blend * 0.3, world_pos.y);
	// Schneedecke im Tal (Winter, Schneefall): fleckig, unter Bäumen und am Wasser weniger
	float cover = snow_cover * (1.0 - COLOR.r * 0.35) * (1.0 - COLOR.b);
	cover = smoothstep(0.0, 0.35, cover - (1.0 - snow_cover) * small_noise * 0.6);
	snow_w = max(snow_w, cover);
	snow_w *= 1.0 - smoothstep(0.30, 0.50, slope + (small_noise - 0.5) * 0.15);
	// Erde/Schotter: im Wald und als schmaler Streifen neben der Straße (Grün-Kanal)
	float dirt_w = clamp(forest * 0.45 + smoothstep(0.5, 1.0, COLOR.g) * 0.6, 0.0, 1.0);
	float alpine_w = smoothstep(tree_line, tree_line + 220.0, world_pos.y + (mid_noise - 0.5) * 120.0);
	vec3 green = mix(grass_color, dry_grass_color, smoothstep(0.55, 0.9, big_noise) * 0.7);
	// Jahreszeit: Frühling frisches Grün, Herbst und Winter bräunlich
	green = mix(green, vec3(0.30, 0.56, 0.10), season_spring * 0.7);
	green = mix(green, vec3(0.42, 0.40, 0.15), season_autumn * 0.45 + season_winter * 0.5);
	vec3 alpine = alpine_color * (0.7 + mid_noise * 0.6);

	// --- Ferne Farben (ohne Texturen) ---
	vec3 far_ground = mix(grade_grass(GRASS_MEAN, green, mid_noise), grade_dirt(DIRT_MEAN), dirt_w);
	far_ground = mix(far_ground, mix(far_ground, alpine, 0.7), alpine_w);
	// Wälder in der Ferne dunkler (im Herbst bunt, im Winter graubraun)
	vec3 forest_tint = mix(vec3(0.55, 0.68, 0.55), vec3(0.9, 0.6, 0.35), season_autumn * 0.6);
	forest_tint = mix(forest_tint, vec3(0.5, 0.48, 0.45), season_winter * 0.5);
	far_ground *= mix(vec3(1.0), forest_tint, forest * far_blend);
	vec3 far_albedo = mix(far_ground, grade_rock(ROCK_MEAN, mid_noise), rock_w);
	far_albedo = mix(far_albedo, grade_snow(SNOW_MEAN), snow_w);

	vec3 albedo = far_albedo;
	vec3 normal_ws = n;
	float roughness = mix(mix(0.95, 0.85, rock_w), 0.55, snow_w);

	if (far_blend < 1.0) {
		// --- Gras: zwei Maßstäbe mischen, damit sich nichts sichtbar wiederholt ---
		vec2 uv_g = world_pos.xz / grass_scale;
		vec3 grass = mix(texture(grass_albedo, uv_g).rgb, texture(grass_albedo, uv_g * 0.23 + 0.37).rgb, 0.4);
		grass = grade_grass(grass, green, mid_noise);
		vec3 grass_n = top_normal(grass_normal, uv_g, n);

		// --- Waldboden / Erde ---
		vec2 uv_d = world_pos.xz / dirt_scale;
		vec3 dirt = grade_dirt(texture(dirt_albedo, uv_d).rgb);
		vec3 dirt_n = top_normal(dirt_normal, uv_d, n);

		// --- Fels: von drei Seiten projiziert ---
		vec3 w = pow(abs(n), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec2 uv_x = world_pos.zy / rock_scale;
		vec2 uv_y = world_pos.xz / rock_scale;
		vec2 uv_z = world_pos.xy / rock_scale;
		vec3 rock = texture(rock_albedo, uv_x).rgb * w.x + texture(rock_albedo, uv_y).rgb * w.y + texture(rock_albedo, uv_z).rgb * w.z;
		rock = grade_rock(rock, mid_noise);
		vec3 tx = unpack_normal(texture(rock_normal, uv_x));
		vec3 ty = unpack_normal(texture(rock_normal, uv_y));
		vec3 tz = unpack_normal(texture(rock_normal, uv_z));
		tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
		ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
		tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
		vec3 rock_n = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);

		// --- Schnee ---
		vec2 uv_s = world_pos.xz / snow_scale;
		vec3 snow = grade_snow(texture(snow_albedo, uv_s).rgb);
		vec3 snow_n = top_normal(snow_normal, uv_s, n);

		// --- Zusammenmischen ---
		vec3 ground = mix(grass, dirt, dirt_w);
		vec3 ground_n = normalize(mix(grass_n, dirt_n, dirt_w));
		ground = mix(ground, mix(ground, alpine, 0.7), alpine_w);
		vec3 near_albedo = mix(ground, rock, rock_w);
		vec3 near_n = normalize(mix(ground_n, rock_n, rock_w));
		near_albedo = mix(near_albedo, snow, snow_w);
		near_n = normalize(mix(near_n, snow_n, snow_w));

		albedo = mix(near_albedo, far_albedo, far_blend);
		normal_ws = normalize(mix(near_n, n, far_blend));
	}

	if (far_mode) {
		// Horizont-Ring: Blau-Kanal = See
		albedo = mix(albedo, vec3(0.02, 0.04, 0.05), COLOR.b);
		roughness = mix(roughness, 0.1, COLOR.b);
	} else {
		// Kacheln: Blau-Kanal = nass. Am Ufer dunkler und glänzender, unter Wasser schlammig.
		float wet = COLOR.b;
		vec3 mud = vec3(0.16, 0.15, 0.10) * mix(0.8, 1.2, mid_noise);
		albedo = mix(albedo, albedo * 0.55, smoothstep(0.0, 0.5, wet));
		albedo = mix(albedo, mud, smoothstep(0.6, 1.0, wet));
		roughness = mix(roughness, 0.35, wet);
		// Regen: alles etwas dunkler und glänzender (Schnee nicht)
		float rain_wet = wetness * (1.0 - snow_w) * (1.0 - far_blend * 0.7);
		albedo *= 1.0 - rain_wet * 0.25;
		roughness = mix(roughness, roughness * 0.75, rain_wet);
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_ws, 0.0)).xyz);
}
