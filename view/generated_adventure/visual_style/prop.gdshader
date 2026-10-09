shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool facet_existing_triangles=false;
varying vec3 world_normal;
varying vec3 world_position;
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void vertex(){world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec3 n=normalize(world_normal);
 if(facet_existing_triangles){
  vec3 face=normalize(cross(dFdx(world_position),dFdy(world_position)));
  n=face*(dot(face,n)<0.0?-1.0:1.0);
 }
 vec3 base=OUTPUT_IS_SRGB?base_color.rgb:encode(base_color.rgb);
 float lit=smoothstep(.23,.30,dot(n,normalize(vec3(-.55,.74,.39))));
 // Small existing crown facets need less contrast at overview size.
 vec3 shade=facet_existing_triangles?vec3(.62,.76,.88):vec3(.55,.70,.86);
 vec3 c=mix(base*shade,base,lit);
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
