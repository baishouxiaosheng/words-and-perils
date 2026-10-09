shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// visual_canopy_cutaway/v1: original unindexed vertices; exact bark prefix.
// Custom data: x=visibility, y=bark vertex prefix, z=woody tree membership.
// The same 0.5 instance-mask threshold is used by the CPU raw picker.
// No ALPHA output or depth prepass: distant opaque forest keeps its depth path.
varying flat float crown_mask;
varying float crown_triangle;
vec3 encode_srgb(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
void vertex() {
 crown_mask=INSTANCE_CUSTOM.x;
 crown_triangle=(INSTANCE_CUSTOM.z>0.5 && float(VERTEX_ID)>=INSTANCE_CUSTOM.y) ? 1.0 : 0.0;
}
void fragment() {
 if (crown_triangle>0.5 && crown_mask<0.5) { discard; }
 ALBEDO=COLOR.rgb;
 if (OUTPUT_IS_SRGB) ALBEDO=encode_srgb(ALBEDO);
 ROUGHNESS=.86;SPECULAR=.27;METALLIC=0.0;
}
