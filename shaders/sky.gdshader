// Himmels-Shader: Farbverlauf, Sonne mit Glühen, Wolken, nachts Sterne und Mond.
// Die Farben setzt das Skript day_night.gd passend zur Uhrzeit.
shader_type sky;


// Richtung ZUR Sonne bzw. zum Mond (Einheitsvektoren)
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);

uniform vec3 zenith_color : source_color = vec3(0.16, 0.40, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.80, 0.95);
uniform vec3 ground_color : source_color = vec3(0.12, 0.13, 0.14);
// Glühen rund um die Sonne (bei Sonnenuntergang kräftig orange)
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float sun_glow_strength = 0.5;
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_disk_energy = 40.0;
// Größe der Sonnen- und Mondscheibe (Winkel in Bogenmaß)
uniform float sun_size = 0.014;
uniform float moon_size = 0.022;
// 0 = Tag, 1 = Nacht (blendet Sterne und Mond ein)
uniform float night_amount = 0.0;
uniform float star_brightness = 2.5;

// Wolken
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_scale = 0.25;
uniform vec2 cloud_wind = vec2(0.0035, 0.0015);
uniform vec3 cloud_light_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.55, 0.6, 0.7);

// Gesamthelligkeit des Himmels
uniform float sky_energy = 1.0;

// Regenbogen (0 = keiner): Kreis mit ~42° um den Punkt gegenüber der Sonne
uniform float rainbow = 0.0;
// Polarlicht (0 = keins): grüne Vorhänge mit violetten Spitzen im Norden (-Z)
uniform float aurora = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Regenbogenfarbe: x = 0 innen (violett) bis 1 außen (rot)
vec3 spectrum(float x) {
	vec3 c = vec3(
		smoothstep(0.45, 0.85, x) + smoothstep(0.25, 0.0, x) * 0.5,
		smoothstep(0.15, 0.5, x) * smoothstep(1.0, 0.6, x),
		smoothstep(0.55, 0.15, x));
	return c * smoothstep(0.0, 0.12, x) * smoothstep(1.0, 0.85, x);
}

// Polarlicht: mehrere Schichten übereinander; jede Schicht ist ein welliger Streifen am
// Nordhimmel, unten grün, oben violett, mit feinen senkrechten Strahlen
vec3 aurora_light(vec3 dir) {
	vec3 sum = vec3(0.0);
	// Strahlen senkrecht: hängen nur von der Himmelsrichtung ab (laufen im Zenit zusammen)
	float azimuth = atan(dir.x, -dir.z);
	for (int i = 0; i < 14; i++) {
		float layer = float(i) / 14.0;
		vec2 q = dir.xz / max(dir.y, 0.02) * (1.0 + layer * 1.5);
		float wave = sin(q.x * 0.45 + TIME * 0.05) * 0.9 + sin(q.x * 1.3 - TIME * 0.08) * 0.35;
		float band = q.y + 3.6 + wave;
		float curtain = exp(-band * band * 1.6);
		float rays = texture(cloud_noise, vec2(azimuth * 2.2 + TIME * 0.008, 0.37 + layer * 0.01)).r;
		curtain *= 0.15 + 2.2 * rays * rays * rays;
		vec3 c = mix(vec3(0.15, 1.0, 0.45), vec3(0.6, 0.25, 1.0), smoothstep(0.3, 0.95, layer));
		sum += c * curtain * (1.0 - layer * 0.6);
	}
	return sum * 0.1 * smoothstep(0.02, 0.12, dir.y) * smoothstep(0.2, -0.3, dir.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);

	// --- Grundfarbe: oben Zenit-Farbe, zum Horizont hin heller ---
	float horizon_t = pow(1.0 - up, 5.0);
	vec3 col = mix(zenith_color, horizon_color, horizon_t);

	// --- Glühen um die Sonne, am Horizont stärker ---
	float cos_sun = dot(dir, sun_direction);
	float glow = pow(max(cos_sun, 0.0), 5.0) * 0.4 + pow(max(cos_sun, 0.0), 40.0) * 0.9;
	col += sun_glow_color * glow * sun_glow_strength * (0.35 + 0.65 * horizon_t);

	// --- Unter dem Horizont: Boden (meist vom Gelände verdeckt) ---
	col = mix(col, ground_color, smoothstep(0.0, -0.1, dir.y));

	// --- Sterne (nur nachts) ---
	if (night_amount > 0.01 && dir.y > 0.0) {
		vec3 p = dir * 350.0;
		vec3 cell = floor(p);
		float r = hash13(cell);
		if (r > 0.9975) {
			vec3 center = cell + 0.5 + (vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 4.1)) - 0.5) * 0.6;
			float d = length(p - center);
			float twinkle = 0.75 + 0.25 * sin(TIME * (1.5 + r * 40.0) + r * 300.0);
			float bright = (r - 0.9975) / 0.0025;
			col += vec3(0.85, 0.9, 1.0) * smoothstep(0.32, 0.0, d) * star_brightness * (0.3 + bright * 1.7)
				* twinkle * night_amount * smoothstep(0.0, 0.2, dir.y);
		}
	}

	// --- Mond: Scheibe mit etwas Struktur und leichtem Hof ---
	float cos_moon = dot(dir, moon_direction);
	float moon_disk = smoothstep(cos(moon_size), cos(moon_size * 0.9), cos_moon);
	if (moon_disk > 0.0) {
		float spots = texture(cloud_noise, (dir.xy - moon_direction.xy) * 18.0 + 0.5).r;
		col = mix(col, vec3(0.85, 0.88, 0.95) * (0.75 + spots * 0.5) * 1.6, moon_disk * night_amount);
	}
	col += vec3(0.35, 0.45, 0.7) * pow(max(cos_moon, 0.0), 300.0) * 0.6 * night_amount;

	// --- Sonnenscheibe ---
	float disk = smoothstep(cos(sun_size), cos(sun_size * 0.8), cos_sun);
	col += sun_disk_color * disk * sun_disk_energy * smoothstep(-0.03, 0.01, dir.y);

	// --- Wolken: flache Schicht, die zum Horizont hin dünner wird ---
	if (dir.y > 0.0) {
		vec2 uv = dir.xz / (dir.y + 0.15) * cloud_scale + cloud_wind * TIME;
		float n = texture(cloud_noise, uv).r * 0.62 + texture(cloud_noise, uv * 2.9 + 0.31).r * 0.38;
		float density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.28, n);
		density *= smoothstep(0.0, 0.15, dir.y);
		// Dichte Stellen dunkler (Unterseite), Ränder hell; zur Sonne hin leuchtende Ränder
		float thickness = smoothstep(1.0 - cloud_coverage + 0.1, 1.0, n);
		vec3 cloud = mix(cloud_light_color, cloud_shadow_color, thickness * 0.8);
		cloud += sun_glow_color * glow * sun_glow_strength * (1.0 - thickness) * 0.8;
		col = mix(col, cloud, density * 0.92);
	}

	// --- Regenbogen: Hauptbogen 40,6–42,3°, schwacher Nebenbogen 50–53° (Farben umgekehrt) ---
	if (rainbow > 0.001 && dir.y > 0.0) {
		float angle = degrees(acos(clamp(dot(dir, -sun_direction), -1.0, 1.0)));
		vec3 bow = spectrum((angle - 40.0) / 2.8) + spectrum((53.5 - angle) / 3.5) * 0.25;
		// Nicht ganz bis zum Horizont, vor dichten Wolken etwas schwächer
		col += bow * rainbow * 0.35 * smoothstep(0.0, 0.08, dir.y);
	}

	// --- Polarlicht ---
	if (aurora > 0.001 && dir.y > 0.0) {
		col += aurora_light(dir) * aurora;
	}

	COLOR = col * sky_energy;
}
