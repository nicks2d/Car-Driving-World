shader_type canvas_item;
// Farbfilter im Fotomodus: 1 = warm, 2 = kühl, 3 = schwarz-weiß (0 = Fläche unsichtbar)

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform int mode = 0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	if (mode == 1) {
		c = c * vec3(1.08, 1.0, 0.84) + vec3(0.015, 0.008, 0.0);
	} else if (mode == 2) {
		c = c * vec3(0.88, 0.97, 1.1);
	} else if (mode == 3) {
		float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
		// Etwas mehr Kontrast, wie ein klassischer S/W-Film
		c = vec3(smoothstep(0.02, 0.98, l));
	}
	COLOR = vec4(c, 1.0);
}
