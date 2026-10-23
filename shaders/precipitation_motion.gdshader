// Bewegung der Regentropfen und Schneeflocken (Partikel-Shader).
// Alle Partikel leben in einem Kasten, der mit der Kamera mitwandert. Sie fallen in der
// Welt nach unten; was unten oder hinten aus dem Kasten fällt, kommt oben bzw. vorne
// wieder herein. So ist es um die Kamera herum bei jedem Tempo gleich dicht.
shader_type particles;
render_mode disable_velocity, disable_force;

uniform vec3 box_size = vec3(36.0, 22.0, 36.0);
// Fallgeschwindigkeit (mit Wind) in Metern pro Sekunde
uniform vec3 fall_velocity = vec3(0.0, -11.0, 0.0);
// Schnee: seitliches Taumeln der Flocken (Meter pro Sekunde)
uniform float flutter = 0.0;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	if (RESTART_POSITION) {
		vec3 r = vec3(hash(INDEX * 3u + 1u), hash(INDEX * 3u + 2u), hash(INDEX * 3u + 3u));
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + (r - 0.5) * box_size;
	}
	// Feste Zufallswerte pro Partikel: x entscheidet, ab welcher Stärke es sichtbar ist
	CUSTOM = vec4(hash(INDEX * 7u + 11u), hash(INDEX * 5u + 3u), 0.0, 0.0);
}

void process() {
	vec3 velocity = fall_velocity;
	if (flutter > 0.0) {
		float phase = CUSTOM.y * 60.0;
		velocity.x += sin(TIME * 1.3 + phase) * flutter;
		velocity.z += cos(TIME * 1.1 + phase * 0.7) * flutter;
	}
	vec3 center = EMISSION_TRANSFORM[3].xyz;
	vec3 relative = TRANSFORM[3].xyz + velocity * DELTA - center;
	// Im Kasten halten (was hinten herausfällt, kommt vorne wieder herein)
	relative = mod(relative + box_size * 0.5, box_size) - box_size * 0.5;
	TRANSFORM[3].xyz = center + relative;
}
