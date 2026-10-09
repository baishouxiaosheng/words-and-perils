shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform vec3 water_color : source_color = vec3(0.224,0.486,0.533);
varying vec3 world_normal;
void vertex() { world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 ALBEDO=water_color;
 ROUGHNESS=0.92;
 METALLIC=0.0;
 SPECULAR=0.08;
 NORMAL=normalize((VIEW_MATRIX*vec4(world_normal,0.0)).xyz);
}
