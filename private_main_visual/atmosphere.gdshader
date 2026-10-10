shader_type spatial;
// Full-screen veil drawn before every other transparent surface. It blends the
// scene toward the sky colour by view depth (aerial haze) and by distance to
// the board's hexagonal outline (edge mist), so the stepped map edge and the
// far ground dissolve into the background instead of ending in a hard cut.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 haze_color : source_color = vec3(.74, .87, .89);
uniform float haze_amount = 0.0;
// View depth where the haze starts and where it reaches haze_amount.
uniform vec2 haze_depth = vec2(10.0, 20.0);
// Board centre (x, z), apothem, and 1 when the corners point along x.
uniform vec4 board = vec4(0.0, 0.0, 1e9, 1.0);
// World units inside the outline over which the mist rises to full.
uniform float edge_mist = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, .5, 1.0);
}

float outline_distance(vec2 p) {
	p = abs(p - board.xy);
	if (board.w < .5) p = p.yx;
	return max(p.y, dot(p, vec2(.8660254, .5))) - board.z;
}

void fragment() {
	float raw = texture(scene_depth, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float haze = haze_amount * smoothstep(haze_depth.x, haze_depth.y, -view.z);
	float mist = edge_mist > 0.0 ? smoothstep(-edge_mist, 0.0, outline_distance(world.xz)) : 0.0;
	ALBEDO = haze_color;
	ALPHA = max(haze, mist);
}
