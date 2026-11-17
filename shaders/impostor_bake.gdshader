// Backen der Baum-Impostoren (TreeImpostors): zeichnet einen Baum ohne Licht, entweder seine Farbe
// (wie foliage.gdshader im Sommer, mit Blattmuster und Borke) oder seine Normale im Modell-Raum
// (Normale * 0,5 + 0,5). Daraus entstehen die Bilder für ferne Bäume.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D leaf_noise : filter_linear_mipmap, repeat_enable;
// false = Farbe, true = Normale
uniform bool normals = false;

varying vec3 local_pos;
varying vec3 model_normal;
varying float bark;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	local_pos = VERTEX;
	model_normal = NORMAL;
	bark = UV.x;
}

void fragment() {
	if (normals) {
		vec3 n = normalize(model_normal);
		if (!FRONT_FACING) {
			n = -n;
		}
		ALBEDO = n * 0.5 + 0.5;
	} else {
		float leaves = texture(leaf_noise, local_pos.xz * 4.0).r * texture(leaf_noise, local_pos.xy * 4.0 + 0.5).r;
		vec3 color = to_linear(COLOR.rgb) * mix(0.55, 1.35, leaves * 1.6);
		if (bark > 0.5) {
			float furrows = texture(leaf_noise, vec2(atan(local_pos.z, local_pos.x) * 0.8, local_pos.y * 9.0)).r;
			color = to_linear(COLOR.rgb) * mix(0.45, 1.25, furrows);
		}
		ALBEDO = color;
	}
}
