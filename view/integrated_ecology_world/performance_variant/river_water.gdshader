shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Visual shallow-river palette only. This is not hydrologic depth or source shore distance.
uniform float visual_shallow_mix=0.72;
varying vec3 wp;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec3 deep=decode(vec3(.23,.42,.43));vec3 shallow=decode(vec3(.47,.66,.57));
 ALBEDO=mix(deep,shallow,visual_shallow_mix);
 if(OUTPUT_IS_SRGB)ALBEDO=encode(ALBEDO);
 vec2 wave=vec2(sin(wp.x*6.7+wp.z*3.3),cos(wp.z*7.1-wp.x*2.8))*.013;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(wave.x,1,wave.y)),0)).xyz);
 ROUGHNESS=.63;SPECULAR=.16;METALLIC=0.0;
}
