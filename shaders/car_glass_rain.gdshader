// Scheiben des Autos (CarModel) mit Regentropfen, solange es regnet (CarModel tauscht den Shader).
// Alles Weitere in car_glass.gdshaderinc.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

#define RAIN_DROPS
#include "res://shaders/car_glass.gdshaderinc"
