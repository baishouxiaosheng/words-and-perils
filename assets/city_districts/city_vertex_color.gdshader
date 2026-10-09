shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// glTF COLOR_0 is linear. Godot's Compatibility renderer calculates lighting
// with sRGB output and ignores BaseMaterial3D.vertex_color_is_srgb. Convert only
// for that renderer; retain correct linear values in Forward+/Mobile.
// https://github.com/godotengine/godot/issues/87486
// https://docs.godotengine.org/en/4.3/tutorials/shaders/shader_reference/spatial_shader.html
vec3 linear_to_display_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 low = c * 12.92;
	vec3 high = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), c));
}

// The authored kit and imported LODs have identical COLOR_0 at each triangle's
// three corners. Flat interpolation keeps the same face-color groups, while
// gamma conversion no longer runs for every covered fragment.
varying flat vec3 city_albedo;

void vertex() {
	vec3 color = COLOR.rgb;
	// A small, hue-preserving lift for the darkest values, mostly timber/window
	// trim (also the darkest slate facets). These are
	// painted face values, not AO or shadow maps. Brighter roof/plaster above
	// display-sRGB 0.52 are unchanged; no silhouette, vertex or material split.
	float value = max(color.r, max(color.g, color.b));
	float dark_trim = 1.0 - smoothstep(0.132868, 0.233022, value);
	color *= 1.0 + 0.16 * dark_trim;
	city_albedo = OUTPUT_IS_SRGB ? linear_to_display_srgb(color) : color;
}

void fragment() {
	ALBEDO = city_albedo;
	ROUGHNESS = 0.91;
	METALLIC = 0.0;
	SPECULAR = 0.20;
}
