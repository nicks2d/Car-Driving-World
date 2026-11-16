// Rückspiegel im Cockpit (Cockpit): zeigt einen Ausschnitt aus dem Bild der Rückkamera, gespiegelt.
// Die Kamera rendert ohne Tonemapping in HDR, die Werte sind also schon linear und hell genug.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform sampler2D view : filter_linear;
// Ausschnitt im Kamerabild: x = links, y = oben, z = rechts, w = unten (0–1)
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
// Spiegel sind etwas dunkler als die Welt
uniform float brightness = 0.85;

void fragment() {
	// Gespiegelt: links im Spiegel ist rechts im Kamerabild
	vec2 uv = vec2(mix(region.z, region.x, UV.x), mix(region.y, region.w, UV.y));
	ALBEDO = texture(view, uv).rgb * brightness;
}
