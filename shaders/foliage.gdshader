// Shader für Bäume und Büsche (MultiMesh).
// Farbe aus den Punktfarben des Modells, pro Baum leicht verändert (INSTANCE_CUSTOM),
// Wind lässt die Krone sanft schwanken, Licht scheint etwas durch die Blätter (BACKLIGHT).
// Jahreszeiten (globale Shader-Werte vom Wetter): Laubbäume (deciduous) werden im Frühling
// hellgrün und im Herbst gelb, orange und rot. Im Winter liegt Schnee auf allem, was nach
// oben zeigt (kahle Laubbäume zeichnet foliage_bare.gdshader).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Wie stark der Wind die Baumkronen bewegt
uniform float wind_strength = 1.0;
// Farbton, mit dem die Pflanzen insgesamt eingefärbt werden
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// Licht, das durch die Blätter scheint
uniform vec3 translucency : source_color = vec3(0.18, 0.24, 0.08);
// Rauschen für das Blattmuster
uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
// Laubbaum oder Busch (färbt sich im Herbst); Nadelbäume bleiben grün
uniform bool deciduous = false;

global uniform float season_spring;
global uniform float season_autumn;
global uniform float snow_cover;
global uniform float snow_line;
global uniform float weather_wind;
#include "res://shaders/cloud_shadow.gdshaderinc"

// Wolkenschatten am Standort (einmal pro Baum bzw. Grasbüschel)
varying float cloud;

varying vec3 instance_tint;
varying vec3 local_pos;
varying float autumn_hue;
varying float tree_height;

void vertex() {
	local_pos = VERTEX;
	// INSTANCE_CUSTOM: r = Helligkeit, g = Gelbstich, b = Zufallswert für den Wind
	float bright = mix(0.8, 1.2, INSTANCE_CUSTOM.r);
	instance_tint = mix(vec3(1.0), vec3(1.15, 1.05, 0.7), INSTANCE_CUSTOM.g * 0.6) * bright;
	autumn_hue = fract(INSTANCE_CUSTOM.b * 7.31 + INSTANCE_CUSTOM.r * 0.5);
	// Wind: je höher am Baum, desto stärker (das Modell ist 1 Einheit hoch)
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	cloud = cloud_shade(origin.xz);
	tree_height = origin.y;
	float phase = TIME * 1.2 + origin.x * 0.05 + origin.z * 0.07 + INSTANCE_CUSTOM.b * 6.28;
	float height = max(VERTEX.y, 0.0);
	float wind = wind_strength * weather_wind;
	VERTEX.x += sin(phase) * 0.012 * height * height * wind;
	VERTEX.z += cos(phase * 0.8) * 0.008 * height * height * wind;
}

// Die Punktfarben der Modelle sind als sRGB gedacht, der Shader rechnet linear
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// Blätter/Nadeln sind grün (G > R), Stämme braun (R > G)
	float leaf = step(COLOR.r, COLOR.g);
	// Blattmuster: zwei Rausch-Ebenen im Modell-Raum ergeben helle und dunkle Blattbüschel
	float leaves = texture(leaf_noise, local_pos.xz * 4.0).r * texture(leaf_noise, local_pos.xy * 4.0 + 0.5).r;
	vec3 color = to_linear(COLOR.rgb) * mix(0.55, 1.35, leaves * 1.6) * tint * instance_tint;
	if (deciduous) {
		float l = luminance(color);
		// Frühling: frisches, helles Grün
		vec3 spring = l * vec3(0.75, 1.55, 0.45) * 1.25;
		// Herbst: jeder Baum eine eigene Farbe zwischen Gelb, Orange und Rot
		vec3 autumn = mix(vec3(0.85, 0.55, 0.04), vec3(0.95, 0.28, 0.03), smoothstep(0.25, 0.55, autumn_hue));
		autumn = mix(autumn, vec3(0.6, 0.06, 0.03), smoothstep(0.7, 0.95, autumn_hue));
		autumn *= l * 4.0;
		color = mix(color, spring, season_spring * leaf);
		color = mix(color, autumn, season_autumn * leaf);
	}
	// Schnee auf allem, was nach oben zeigt (Winter oder oberhalb der Schneegrenze)
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float snow_here = max(snow_cover, smoothstep(snow_line - 120.0, snow_line + 40.0, tree_height));
	// Nadelbäume nicht ganz weiß: unten an den Zweigen bleibt es grün
	float snow = snow_here * smoothstep(0.35, 0.8, world_normal.y + (leaves - 0.3) * 0.9) * 0.9;
	ALBEDO = mix(color, vec3(0.8, 0.82, 0.86), snow);
	ALBEDO *= 1.0 - cloud * 0.5;
	ROUGHNESS = mix(0.85, 0.7, snow);
	SPECULAR = 0.25;
	BACKLIGHT = translucency * (1.0 - snow) * mix(vec3(1.0), vec3(1.8, 0.9, 0.3), season_autumn * float(deciduous));
}
