// Läufer der Strahlventilatoren im Tunnel (TunnelDetails): dreht sich langsam um die Achse des Gehäuses
// (lokal z). Jeder Ventilator etwas anders schnell (aus der Nummer im MultiMesh), keine Arbeit auf der CPU.
shader_type spatial;

uniform vec3 color : source_color = vec3(0.55, 0.56, 0.58);
// Umdrehungen pro Sekunde
uniform float turns = 0.6;

void vertex() {
	float speed = turns * (0.75 + 0.5 * fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453));
	float a = TIME * TAU * speed;
	mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xy = r * VERTEX.xy;
	NORMAL.xy = r * NORMAL.xy;
}

void fragment() {
	ALBEDO = color;
	METALLIC = 0.25;
	ROUGHNESS = 0.45;
}
