// Shader für Bäume und Büsche (MultiMesh).
// Farbe aus den Punktfarben des Modells, pro Baum leicht verändert (INSTANCE_CUSTOM),
// Wind lässt die Krone sanft schwanken, Licht scheint etwas durch die Blätter (BACKLIGHT).
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

varying vec3 instance_tint;
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	// INSTANCE_CUSTOM: r = Helligkeit, g = Gelbstich, b = Zufallswert für den Wind
	float bright = mix(0.8, 1.2, INSTANCE_CUSTOM.r);
	instance_tint = mix(vec3(1.0), vec3(1.15, 1.05, 0.7), INSTANCE_CUSTOM.g * 0.6) * bright;
	// Wind: je höher am Baum, desto stärker (das Modell ist 1 Einheit hoch)
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 1.2 + origin.x * 0.05 + origin.z * 0.07 + INSTANCE_CUSTOM.b * 6.28;
	float height = max(VERTEX.y, 0.0);
	VERTEX.x += sin(phase) * 0.012 * height * height * wind_strength;
	VERTEX.z += cos(phase * 0.8) * 0.008 * height * height * wind_strength;
}

// Die Punktfarben der Modelle sind als sRGB gedacht, der Shader rechnet linear
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	// Blattmuster: zwei Rausch-Ebenen im Modell-Raum ergeben helle und dunkle Blattbüschel
	float leaves = texture(leaf_noise, local_pos.xz * 4.0).r * texture(leaf_noise, local_pos.xy * 4.0 + 0.5).r;
	vec3 color = to_linear(COLOR.rgb) * mix(0.55, 1.35, leaves * 1.6);
	ALBEDO = color * tint * instance_tint;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = translucency;
}
