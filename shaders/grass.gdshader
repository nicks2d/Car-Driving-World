// Gras-Shader (MultiMesh mit vielen Grasbüscheln).
// UV.y geht von 0 (Wurzel) bis 1 (Spitze): unten dunkel, oben hell, oben bewegt der Wind am meisten.
// Am Rand des Grasbereichs schrumpfen die Büschel, damit das Gras nicht hart aufhört.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 root_color : source_color = vec3(0.14, 0.22, 0.06);
uniform vec3 tip_color : source_color = vec3(0.38, 0.55, 0.16);
uniform vec3 dry_color : source_color = vec3(0.55, 0.52, 0.25);
uniform float wind_strength = 1.0;
// Ab hier wird das Gras kleiner, bei fade_end ist es verschwunden (Meter zur Kamera)
uniform float fade_start = 36.0;
uniform float fade_end = 54.0;
// Jahreszeit-Farben: Frühling frischer, Herbst bräunlicher
uniform vec3 spring_tip_color : source_color = vec3(0.42, 0.66, 0.16);
uniform vec3 autumn_tip_color : source_color = vec3(0.55, 0.47, 0.2);

global uniform float season_spring;
global uniform float season_autumn;
global uniform float snow_cover;
global uniform float wetness;
global uniform float weather_wind;

varying float tip;
varying vec3 variation;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float distance = length(origin - CAMERA_POSITION_WORLD);
	// Unter Schnee verschwindet das Gras
	float shrink = (1.0 - smoothstep(fade_start, fade_end, distance)) * (1.0 - smoothstep(0.3, 0.7, snow_cover));
	VERTEX *= shrink;
	// Wind: Böen laufen als Welle über die Wiese
	float gust = sin(TIME * 1.8 + origin.x * 0.25 + origin.z * 0.18) * 0.5 + 0.5;
	float sway = UV.y * UV.y * wind_strength * weather_wind * (0.06 + gust * 0.1);
	VERTEX.x += sin(TIME * 2.3 + origin.z * 0.4) * sway;
	VERTEX.z += cos(TIME * 2.0 + origin.x * 0.4) * sway * 0.7;
	tip = UV.y;
	variation = vec3(INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g, 0.0);
	// Normale nach oben: Gras wird wie eine Fläche beleuchtet, das wirkt ruhiger
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.7);
}

void fragment() {
	vec3 tip_now = mix(tip_color, spring_tip_color, season_spring);
	tip_now = mix(tip_now, autumn_tip_color, season_autumn);
	vec3 top = mix(tip_now, dry_color, smoothstep(0.55, 1.0, variation.g) * 0.6);
	// Nass: etwas dunkler und glänzender
	ALBEDO = mix(root_color, top, tip) * mix(0.8, 1.15, variation.r) * (1.0 - wetness * 0.2);
	ROUGHNESS = mix(0.9, 0.55, wetness);
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.2, 0.28, 0.08) * tip;
}
