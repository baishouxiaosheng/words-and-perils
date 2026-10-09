shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float width_scale = 1.0;
void vertex() {
 VERTEX.xz += UV2 * (width_scale - 1.0);
}
void fragment() {
 ALBEDO = vec3(0.022,0.027,0.015);
 ALPHA = 0.28;
}
