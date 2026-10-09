shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
varying vec3 wn;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void vertex(){wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 c=base_color.rgb;
 // source_color uniforms are sRGB in Compatibility, linear in Forward+.
 if(!OUTPUT_IS_SRGB)c=mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));
 float lit=smoothstep(.20,.30,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
 c=mix(c*vec3(.55,.67,.83),c,lit);
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
