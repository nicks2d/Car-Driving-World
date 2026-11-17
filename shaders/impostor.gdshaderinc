// Ferne Bäume als Impostor (TreeImpostors): ein Viereck, das sich zur Kamera dreht und das Bild des Baums
// aus dem passenden der 8 Blickwinkel zeigt (die zwei nächsten weich überblendet). Licht kommt aus den
// mitgebackenen Normalen, Jahreszeiten, Schnee und Wind wie in foliage.gdshaderinc.
// Eingebunden von impostor.gdshader und impostor_fade.gdshader (FADE_OUT: gerastert ausblenden).

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
// Ohne source_color: Die Normalen werden wie gespeichert gelesen (mit sRGB-Umrechnung zeigten sie zu oft
// nach unten, ferne Bäume waren fast schwarz)
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
// Anzahl der Blickwinkel im Bild (nebeneinander)
uniform float frames = 8.0;
uniform float wind_strength = 1.0;
uniform vec3 translucency : source_color = vec3(0.18, 0.24, 0.08);
uniform bool deciduous = false;
// Winter: Laubbäume kahl (nur ein lockeres Geflecht bleibt)
uniform bool bare = false;
uniform vec3 bark_color : source_color = vec3(0.24, 0.2, 0.17);

global uniform float season_spring;
global uniform float season_autumn;
global uniform float snow_cover;
global uniform float snow_line;
global uniform float weather_wind;
#include "res://shaders/cloud_shadow.gdshaderinc"

#ifdef FADE_OUT
instance uniform float fade_out = 1.0;
#endif

varying float cloud;
varying vec3 instance_tint;
varying float autumn_hue;
varying float tree_height;
varying flat vec3 frame_info;
// Drehung des einzelnen Baums (im Fragment-Teil enthält MODEL_MATRIX bei MultiMeshes nur die Lage des ganzen
// MultiMesh, nicht die des Exemplars)
varying vec3 axis_x;
varying vec3 axis_y;
varying vec3 axis_z;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	float bright = mix(0.8, 1.2, INSTANCE_CUSTOM.r);
	instance_tint = mix(vec3(1.0), vec3(1.15, 1.05, 0.7), INSTANCE_CUSTOM.g * 0.6) * bright;
	autumn_hue = fract(INSTANCE_CUSTOM.b * 7.31 + INSTANCE_CUSTOM.r * 0.5);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	axis_x = normalize(MODEL_MATRIX[0].xyz);
	axis_y = normalize(MODEL_MATRIX[1].xyz);
	axis_z = normalize(MODEL_MATRIX[2].xyz);
	cloud = cloud_shade(origin.xz);
	tree_height = origin.y;
	// Kamera im Modell-Raum: daraus Blickrichtung (waagerecht) und das passende Bild
	vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 d = normalize(camera_local.xz + vec2(0.0001, 0.0));
	float angle = atan(d.x, d.y);
	float f = fract(angle / 6.28318) * frames;
	float f0 = mod(floor(f), frames);
	frame_info = vec3(f0, mod(f0 + 1.0, frames), fract(f));
	// Viereck quer zur Blickrichtung drehen
	vec3 right = vec3(d.y, 0.0, -d.x);
	float y = VERTEX.y;
	float phase = TIME * 1.2 + origin.x * 0.05 + origin.z * 0.07 + INSTANCE_CUSTOM.b * 6.28;
	float sway = sin(phase) * 0.012 * y * y * wind_strength * weather_wind;
	VERTEX = right * (VERTEX.x + sway) + vec3(0.0, y, 0.0);
	NORMAL = vec3(d.x, 0.0, d.y);
}

void fragment() {
	vec2 uv0 = vec2((frame_info.x + UV.x) / frames, UV.y);
	vec2 uv1 = vec2((frame_info.y + UV.x) / frames, UV.y);
	vec4 a = mix(texture(albedo_atlas, uv0), texture(albedo_atlas, uv1), frame_info.z);
	vec3 n_model = mix(texture(normal_atlas, uv0).rgb, texture(normal_atlas, uv1).rgb, frame_info.z) * 2.0 - 1.0;
#ifdef FADE_OUT
	float threshold = fract(dot(floor(FRAGCOORD.xy), vec2(0.0625, 0.25)) + fract(FRAGCOORD.y * 0.25) * 0.5);
	if (threshold >= fade_out) {
		discard;
	}
#endif
	vec3 color = a.rgb * instance_tint;
	float leaf = step(color.r, color.g);
	if (deciduous) {
		float l = luminance(color);
		vec3 spring = l * vec3(0.75, 1.55, 0.45) * 1.25;
		vec3 autumn = mix(vec3(0.85, 0.55, 0.04), vec3(0.95, 0.28, 0.03), smoothstep(0.25, 0.55, autumn_hue));
		autumn = mix(autumn, vec3(0.6, 0.06, 0.03), smoothstep(0.7, 0.95, autumn_hue));
		autumn *= l * 4.0;
		color = mix(color, spring, season_spring * leaf);
		color = mix(color, autumn, season_autumn * leaf);
	}
	float alpha = a.a;
	if (bare && leaf > 0.5) {
		// Kahle Krone: nur ein lockeres Geflecht aus dem Rauschen bleibt
		float twigs = texture(leaf_noise, UV * vec2(3.0, 6.0) + frame_info.x * 0.37).r;
		alpha *= step(0.62, twigs);
		color = bark_color;
	}
	vec3 world_normal = normalize(axis_x * n_model.x + axis_y * n_model.y + axis_z * n_model.z);
	float snow_here = max(snow_cover, smoothstep(snow_line - 120.0, snow_line + 40.0, tree_height));
	float snow = snow_here * smoothstep(0.35, 0.8, world_normal.y) * 0.9;
	ALBEDO = mix(color, vec3(0.8, 0.82, 0.86), snow) * (1.0 - cloud * 0.5);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALPHA = alpha;
	// Etwas niedrigere Schwelle: in den kleinen Bildstufen ist die Deckung gemittelt, sonst dünnen die
	// Bäume in der Ferne aus
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = translucency * (1.0 - snow) * leaf;
}
