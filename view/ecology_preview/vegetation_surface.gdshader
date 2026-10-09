shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
vec3 encode_srgb(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
void fragment() {
 // Mesh and deterministic instance variation are authored in linear RGB.
 ALBEDO=COLOR.rgb;
 if (OUTPUT_IS_SRGB) ALBEDO=encode_srgb(ALBEDO);
 ROUGHNESS=.86;SPECULAR=.27;METALLIC=0.0;
}
