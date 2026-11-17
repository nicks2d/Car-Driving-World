// Bildeffekt beim Zurückspulen (Rewind): fast schwarz-weiß, leicht bläulich, wandernde Streifen und
// ab und zu ein helles Störband wie bei einer zurückgespulten Videokassette.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;

void fragment() {
	// Bild leicht seitlich versetzt (wackelndes Band)
	float wobble = sin(SCREEN_UV.y * 40.0 + TIME * 23.0) * 0.0015;
	vec3 color = texture(screen, SCREEN_UV + vec2(wobble, 0.0)).rgb;
	float grey = dot(color, vec3(0.3, 0.59, 0.11));
	color = mix(color, vec3(grey) * vec3(0.88, 0.95, 1.1), 0.8);
	float stripe = 0.5 + 0.5 * sin(SCREEN_UV.y * 220.0 + TIME * 60.0);
	color *= 0.88 + 0.12 * stripe;
	float band = smoothstep(0.04, 0.0, abs(fract(SCREEN_UV.y * 0.8 + TIME * 0.9) - 0.5));
	color += band * 0.15;
	// Ränder dunkler
	vec2 centered = SCREEN_UV - 0.5;
	color *= 1.0 - dot(centered, centered) * 0.9;
	COLOR = vec4(color, 1.0);
}
