// Gelände-Kachel, die beim Wechsel der Detailstufe gerastert ausgeblendet wird (TerrainManager, nur kurz).
// Alles Weitere in terrain.gdshaderinc.
shader_type spatial;
#define FADE_OUT
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain.gdshaderinc"
