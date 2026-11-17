// Bäume und Büsche, die beim Wechsel der Detailstufe gerastert ausgeblendet werden (TerrainManager, nur
// für die kurze Zeit des Übergangs: discard kostet auf dem Mac). Alles Weitere in foliage.gdshaderinc.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#define FADE_OUT
#include "res://shaders/foliage.gdshaderinc"
