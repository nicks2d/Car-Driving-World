// Kahle Laubbäume im Winter (gleiches Modell wie im Sommer).
// Von der Krone bleibt nur ein lockeres Geflecht aus dünnen „Zweigen“ übrig: Das Rauschen
// schneidet den größten Teil weg (discard), der Rest ist graubraun, oben liegt Schnee.
// Eigener Shader, weil discard etwas Rechenzeit kostet; im Sommer wird er nicht benutzt.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float wind_strength = 1.0;
uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
// Wie viel von der Krone stehen bleibt (0 = nichts, 1 = alles)
uniform float twig_density = 0.3;
uniform vec3 bark_color : source_color = vec3(0.24, 0.2, 0.17);

global uniform float snow_cover;
global uniform float weather_wind;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 1.2 + origin.x * 0.05 + origin.z * 0.07 + INSTANCE_CUSTOM.b * 6.28;
	float height = max(VERTEX.y, 0.0);
	float wind = wind_strength * weather_wind * 0.6;
	VERTEX.x += sin(phase) * 0.012 * height * height * wind;
	VERTEX.z += cos(phase * 0.8) * 0.008 * height * height * wind;
}

void fragment() {
	float leaf = step(COLOR.r, COLOR.g);
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 color = bark_color * mix(0.7, 1.1, texture(leaf_noise, local_pos.xy * 3.0).r);
	if (leaf > 0.5) {
		// Feines Muster aus zwei Richtungen: wirkt wie verästelte Zweige
		float twigs = texture(leaf_noise, local_pos.xz * 11.0 + local_pos.y * 2.0).r
			* texture(leaf_noise, local_pos.xy * 9.0 + 0.3).r;
		if (twigs < 1.0 - twig_density - 0.45) {
			discard;
		}
		color *= 0.75;
	}
	float snow = snow_cover * smoothstep(0.2, 0.7, world_normal.y);
	ALBEDO = mix(color, vec3(0.8, 0.82, 0.86), snow);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
