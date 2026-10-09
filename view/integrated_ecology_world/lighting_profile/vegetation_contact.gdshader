shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
varying float local_height;
vec3 encode_srgb(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
void vertex(){local_height=VERTEX.y;}
void fragment(){
 float self_contact=mix(.79,1.0,smoothstep(.18,.91,local_height));
 ALBEDO=COLOR.rgb*self_contact;
 if(OUTPUT_IS_SRGB)ALBEDO=encode_srgb(ALBEDO);
 ROUGHNESS=.88;SPECULAR=.20;METALLIC=0.0;
}
