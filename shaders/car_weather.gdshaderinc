// Wetter am Auto (CarWeather): Tropfen, Schnee und Eis. Eingebunden vom Glas (car_glass.gdshaderinc) und
// vom Lack-Zusatzdurchgang (car_paint_fx.gdshader). Alle Lagen in Auto-Koordinaten (x quer, y hoch,
// z nach vorne), Normalen ebenso.

float weather_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Weiches Rauschen 0–1 (Wertrauschen)
float weather_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = weather_hash(i);
	float b = weather_hash(i + vec2(1.0, 0.0));
	float c = weather_hash(i + vec2(0.0, 1.0));
	float d = weather_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Eine Schicht Tropfen: xy = Richtung der Wölbung (Brechung, Glanz), z = Deckung 0–1.
// p: Lage auf der Fläche in Zellen, stretch: Länge der Tropfen in Laufrichtung (y)
vec3 drop_layer(vec2 p, float amount, float stretch, float seed) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = weather_hash(cell + seed);
	// Nicht jede Zelle hat einen Tropfen: je nasser, desto mehr
	if (h > amount) {
		return vec3(0.0);
	}
	vec2 center = (vec2(weather_hash(cell + seed + 3.1), weather_hash(cell + seed + 7.7)) - 0.5) * 0.5;
	float radius = mix(0.14, 0.34, weather_hash(cell + seed + 1.9));
	vec2 d = (f - center) / vec2(1.0, stretch);
	float r = length(d) / radius;
	float cover = smoothstep(1.0, 0.75, r);
	return vec3(d / radius * cover, cover);
}

// Koordinaten auf einer Fläche: side und up liegen in der Fläche (up = die Fläche hinauf; auf dem Dach
// nach vorne)
void surface_axes(vec3 n, out vec3 side, out vec3 up) {
	up = vec3(0.0, 1.0, 0.0) - n * n.y;
	up = length(up) > 0.01 ? normalize(up) : vec3(0.0, 0.0, 1.0);
	side = normalize(cross(n, up));
}

// Tropfen auf einer Fläche: ruhende und laufende. Im Stand rutschen sie langsam nach unten, beim Fahren
// drückt der Fahrtwind sie nach hinten. wet: wie nass (0–1), speed: Tempo (m/s), cell: Zellgröße (m).
// Ergebnis wie drop_layer, xy in den Achsen side/up.
vec3 car_drops(vec3 pos, vec3 n, float speed, float wet, float time, float cell) {
	vec3 side;
	vec3 up;
	surface_axes(n, side, up);
	vec2 p = vec2(dot(pos, side), dot(pos, up)) / cell;
	// Fahrtwind (nach hinten über die Fläche) gegen Schwerkraft (nach unten)
	vec3 wind = vec3(0.0, 0.0, -1.0) - n * (-n.z);
	vec2 wind2 = vec2(dot(wind, side), dot(wind, up));
	float blow = clamp(speed / 25.0, 0.0, 1.0);
	// Auf fast waagerechten Flächen laufen Tropfen im Stand nicht
	float slope = clamp(1.0 - abs(n.y), 0.0, 1.0);
	vec2 flow = normalize(mix(vec2(0.0, -1.0), length(wind2) > 0.01 ? normalize(wind2) : vec2(0.0, -1.0), blow));
	// Ruhende Tropfen (werden mit der Zeit neu verteilt)
	float epoch = floor(time * 0.25 + weather_hash(floor(p)) * 4.0);
	vec3 still = drop_layer(p, wet * 0.55 * (1.0 - blow * 0.6), 1.0, epoch);
	// Laufende Tropfen: in Laufrichtung gedreht, ziehen mit dem Tempo Schlieren
	vec2 q = vec2(dot(p, vec2(flow.y, -flow.x)), dot(p, flow)) * vec2(0.8, 0.5);
	q.y -= time * mix(0.6 * slope, 9.0, blow);
	vec3 running = drop_layer(q, wet * 0.35 * max(slope, blow), mix(1.4, 3.5, blow), 17.0);
	return still.z > running.z ? still : running;
}

// Schnee auf nach oben zeigenden Flächen: Deckung 0–1, wächst mit amount von den flachsten Stellen aus
float car_snow(vec3 pos, vec3 n, float amount) {
	if (amount <= 0.001) {
		return 0.0;
	}
	float noise = weather_noise(pos.xz * 9.0) * 0.6 + weather_noise(pos.xz * 31.0) * 0.4;
	// Nur auf Flächen, die deutlich nach oben zeigen (Seitenwände bleiben frei)
	float level = n.y * 0.8 + noise * 0.3;
	float edge = 1.0 - amount * 0.55;
	return smoothstep(edge, edge + 0.08, level);
}

// Eis auf den Scheiben: Deckung 0–1. Beim Abtauen wird es unten zuerst frei (Gebläse), mit Eisblumen-
// Rand. h: Höhe auf der Scheibe 0 (unten) bis 1 (oben).
float car_frost(vec3 pos, float h, float amount) {
	if (amount <= 0.001) {
		return 0.0;
	}
	float noise = weather_noise(pos.xy * 14.0 + pos.zz * 9.0) * 0.6 + weather_noise(pos.zx * 55.0) * 0.4;
	float level = amount * 1.7 - (1.0 - h) * 0.45 - noise * 0.35;
	return smoothstep(0.0, 0.25, level);
}
