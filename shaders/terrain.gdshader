// Gelände-Shader: mischt Gras, Waldboden, Fels und Schnee je nach Steigung und Höhe.
// Texturen werden über die Welt-Position gelegt (keine UVs nötig).
// Fels wird „triplanar“ von drei Seiten projiziert, damit steile Hänge nicht verzerrt sind.
// Die Normal-Maps werden selbst in Welt-Koordinaten verrechnet und dann an Godot übergeben.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/terrain.gdshaderinc"
