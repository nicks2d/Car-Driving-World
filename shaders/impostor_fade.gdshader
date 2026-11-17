// Ferne Bäume als Impostor, gerastert ausgeblendet beim Wechsel der Detailstufe (TerrainManager).
// Alles Weitere in impostor.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#define FADE_OUT
#include "res://shaders/impostor.gdshaderinc"
