// Beton der Staumauer: hellgrau, waagerechte Arbeitsfugen alle 2,5 m und senkrechte Blockfugen
// alle 16 m (aus der Weltlage), etwas fleckig, nach unten feucht und dunkler.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 concrete : source_color = vec3(0.52, 0.51, 0.48);

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lift = abs(fract(world.y / 2.5) - 0.5);
	float joint = 1.0 - smoothstep(0.45, 0.5, lift) * 0.45;
	float block = 1.0 - smoothstep(0.48, 0.5, abs(fract((world.x + world.z) / 16.0) - 0.5)) * 0.35;
	// Flecken und senkrechte Wasserspuren (Kalk, Feuchtigkeit), die nach unten dunkler werden
	float stain = value_noise(world.xz * 0.15 + world.y * 0.08) * 0.18 + value_noise(world.xy * 0.9) * 0.06;
	float streak = value_noise(vec2((world.x + world.z) * 1.7, world.y * 0.05));
	vec3 color = concrete * (0.82 + stain) * joint * block * (1.0 - smoothstep(0.55, 0.85, streak) * 0.25);
	ALBEDO = color;
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
}
