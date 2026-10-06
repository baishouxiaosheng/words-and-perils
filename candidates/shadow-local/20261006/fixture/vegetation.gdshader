shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 wn;
varying float local_height;
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void vertex(){wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);local_height=VERTEX.y;}
void fragment(){
 vec3 source=encode(COLOR.rgb);
 float leaf=step(source.r*.99,source.g);
 float tropical=smoothstep(.65,.86,source.b/max(source.r,.001));
 vec3 crown=mix(vec3(.514,.678,.310),vec3(.25,.63,.46),tropical);
 float variation=clamp(source.g/.52,.82,1.12);
 vec3 base=mix(vec3(.56,.36,.24)*variation,crown*variation,leaf);
 float lit=smoothstep(.23,.34,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
 vec3 c=mix(base*vec3(.54,.72,.86),base,lit);
 c*=mix(.86,1.0,smoothstep(.18,.90,local_height));
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
