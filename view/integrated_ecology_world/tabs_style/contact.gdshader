shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Reuses the existing pawn contact mesh. Only tint/opacity and visual scale change.
void fragment(){ALBEDO=vec3(.10,.20,.25);ALPHA=COLOR.a*2.15;}
