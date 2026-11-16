// Gemeinsamer Teil der Scheiben des Autos (CarModel): dunkles, leicht spiegelndes Glas. Fenster runter (Taste V):
// Seitenscheiben (Fläche zeigt zur Seite) verschwinden von oben bis zur Brüstungslinie.
// Lage im Auto: car_inverse rechnet Welt- in Auto-Koordinaten (x quer, y hoch, z nach vorne).
// Regen (rain_amount vom Wetter): Tropfen auf den Scheiben, die das Bild dahinter brechen. Im Stand
// rutschen sie langsam nach unten, beim Fahren drückt der Fahrtwind sie über die Scheibe nach hinten.
// In der Cockpit-Sicht (inside = 1) sind die Scheiben von innen fast klar.
// Eingebunden von car_glass.gdshader (trocken) und car_glass_rain.gdshader (mit Tropfen, RAIN_DROPS).

global uniform float rain_amount;

uniform vec4 glass_color : source_color = vec4(0.03, 0.04, 0.05, 0.6);
// 0 = zu, 1 = ganz unten
uniform float window_open = 0.0;
uniform mat4 car_inverse;
// Höhe der Brüstung und der Oberkante der Scheiben im Auto (Meter)
uniform float belt_y = 0.9;
uniform float top_y = 1.3;
// Tempo des Autos (m/s) und Kamera im Auto (0 oder 1)
uniform float car_speed = 0.0;
uniform float inside = 0.0;
// Deckkraft der Scheiben von innen
uniform float inside_opacity = 0.1;
// Größe der Tropfen-Zellen in Metern (ein Tropfen pro Zelle)
uniform float drop_cell = 0.022;
#ifdef RAIN_DROPS
// Nur in der Regen-Variante: Das Bild hinter der Scheibe abgreifen kostet eine Kopie des ganzen Bilds
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
#endif

varying vec3 car_pos;
varying vec3 car_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Eine Schicht Tropfen: xy = Brechung (Richtung, in der das Bild verschoben wird), z = Deckung 0–1.
// p: Lage auf der Scheibe in Zellen, stretch: Länge der Tropfen in Laufrichtung (y)
vec3 drop_layer(vec2 p, float amount, float stretch, float seed) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell + seed);
	// Nicht jede Zelle hat einen Tropfen: je mehr Regen, desto mehr
	if (h > amount) {
		return vec3(0.0);
	}
	vec2 center = (vec2(hash(cell + seed + 3.1), hash(cell + seed + 7.7)) - 0.5) * 0.5;
	float radius = mix(0.14, 0.34, hash(cell + seed + 1.9));
	vec2 d = (f - center) / vec2(1.0, stretch);
	float r = length(d) / radius;
	float cover = smoothstep(1.0, 0.75, r);
	return vec3(d / radius * cover, cover);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	car_pos = (car_inverse * vec4(world, 1.0)).xyz;
	car_normal = normalize(mat3(car_inverse) * (mat3(MODEL_MATRIX) * NORMAL));
}

void fragment() {
	if (window_open > 0.001 && abs(car_normal.x) > 0.55
			&& car_pos.y > top_y - window_open * (top_y - belt_y + 0.02)) {
		discard;
	}
	float alpha = mix(glass_color.a, inside_opacity, inside);
	vec3 albedo = glass_color.rgb;
	vec3 emission = vec3(0.0);
	float roughness = 0.03;
#ifdef RAIN_DROPS
	if (rain_amount > 0.01) {
		// Koordinaten auf der Scheibe: up = die Scheibe hinauf, side = quer dazu
		vec3 n = car_normal;
		vec3 up = vec3(0.0, 1.0, 0.0) - n * n.y;
		up = length(up) > 0.01 ? normalize(up) : vec3(0.0, 0.0, 1.0);
		vec3 side = normalize(cross(n, up));
		vec2 p = vec2(dot(car_pos, side), dot(car_pos, up)) / drop_cell;
		// Fahrtwind (nach hinten über die Scheibe) gegen Schwerkraft (nach unten)
		vec3 wind = vec3(0.0, 0.0, -1.0) - n * (-n.z);
		vec2 wind2 = vec2(dot(wind, side), dot(wind, up));
		float blow = clamp(car_speed / 25.0, 0.0, 1.0);
		vec2 flow = normalize(mix(vec2(0.0, -1.0), length(wind2) > 0.01 ? normalize(wind2) : vec2(0.0, -1.0), blow));
		// Ruhende Tropfen (werden mit der Zeit neu verteilt)
		float epoch = floor(TIME * 0.25 + hash(floor(p)) * 4.0);
		vec3 still = drop_layer(p, rain_amount * 0.55 * (1.0 - blow * 0.6), 1.0, epoch);
		// Laufende Tropfen: in Laufrichtung gedreht, ziehen mit dem Tempo Schlieren
		vec2 q = vec2(dot(p, vec2(flow.y, -flow.x)), dot(p, flow)) * vec2(0.8, 0.5);
		q.y -= TIME * mix(0.6, 9.0, blow);
		vec3 running = drop_layer(q, rain_amount * 0.35, mix(1.4, 3.5, blow), 17.0);
		vec3 drop = still.z > running.z ? still : running;
		if (drop.z > 0.01) {
			// Das Bild hinter dem Tropfen gebrochen (umgedreht und verschoben) zeigen
			vec3 behind = texture(screen_tex, SCREEN_UV - drop.xy * 0.025).rgb;
			emission = behind * drop.z * 0.9;
			albedo *= 1.0 - drop.z;
			alpha = mix(alpha, 1.0, drop.z * 0.85);
			roughness = 0.0;
		}
	}
#endif
	ALBEDO = albedo;
	EMISSION = emission;
	ALPHA = alpha;
	METALLIC = 0.2;
	ROUGHNESS = roughness;
}
