shader_type spatial;
render_mode unshaded, cull_disabled;
// Original flat-faced miniature rock palette. No bitmap or surface-noise texture.
uniform sampler2D visual_weights : filter_linear, repeat_disable;
uniform vec2 world_min=vec2(-44.1673,-38.5);
uniform vec2 world_extent=vec2(88.3346,77.0);
varying vec3 wn;
varying vec2 world_xz;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void vertex(){wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);world_xz=(MODEL_MATRIX*vec4(VERTEX,1)).xz;}
void fragment(){
 vec3 n=normalize(wn);
 float key=dot(n,normalize(vec3(-.55,.74,.39)));
 float lit=smoothstep(.34,.44,key);
 vec3 rock=vec3(.68,.72,.79)*COLOR.r;
 // Gentle directional values inside each broad light group expose real rock planes.
 rock*=.86+.14*clamp((key+.2)/1.2,0.0,1.0);
 vec4 w=texture(visual_weights,(world_xz-world_min)/world_extent);
 w=max(w,vec4(0));w/=max(dot(w,vec4(1)),.000001);
 vec3 foot=(w.r+w.g)*vec3(.659,.788,.373)+w.b*vec3(.606,.788,.384)+w.a*vec3(.80,.68,.39);
 vec3 shade=rock*vec3(.58,.65,.81);
 vec3 c=mix(shade,rock,lit);
 // A narrow color-only join returns precisely to the existing biome palette.
 // Summit and shoulder faces remain matte and flat, without photographic grain.
 c=mix(c,foot,(1.0-smoothstep(.025,.14,COLOR.g*4.0)));
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
