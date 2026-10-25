// Wolkenschatten: ein großes Rauschmuster zieht mit dem Wind übers Land. Die Werte setzt
// Weather (Bedeckung, Stärke, Verschiebung). Gemeinsam für Gelände, Straßen, Bäume und Gras.
global uniform float cloud_shadow;
global uniform float cloud_cover;
global uniform vec2 cloud_offset;
global uniform sampler2D cloud_shadow_noise;

// 0 = Sonne, 1 = voller Wolkenschatten (geht auch im Vertex-Shader: textureLod)
float cloud_shade(vec2 xz) {
	if (cloud_shadow < 0.01) {
		return 0.0;
	}
	vec2 uv = (xz + cloud_offset) / 1400.0;
	float c = textureLod(cloud_shadow_noise, fract(uv), 0.0).r * 0.65
		+ textureLod(cloud_shadow_noise, fract(uv * 2.7 + 0.21), 0.0).r * 0.35;
	// Schwelle passend zur Bedeckung: klar (0,3) etwa 15 % Schatten, bewölkt (0,72) gut die Hälfte
	float threshold = 0.6 - (cloud_cover - 0.3) * 0.36;
	return smoothstep(threshold, threshold + 0.04, c) * cloud_shadow;
}
