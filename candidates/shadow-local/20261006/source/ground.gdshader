shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
// Original authored daylight palette inspired by observed TABS gameplay.
// Two broad light groups; no source mask, shore geometry or vertex displacement.
uniform float shared_woodland_ground = 1.0;
uniform float shore_bands = 1.0;
uniform float visual_blend = 0.0;
uniform sampler2D visual_weights : filter_linear, repeat_disable;
uniform vec2 world_min = vec2(-44.1673,-38.5);
uniform vec2 world_extent = vec2(88.3346,77.0);
uniform sampler2D shore_distance_tile : filter_linear, repeat_disable;
uniform vec2 shore_tile_min = vec2(0.0);
uniform vec2 shore_tile_extent = vec2(1.0);
uniform float shore_distance_cap = 0.45;
uniform float use_shore_tile = 0.0;
uniform sampler2D canopy_contact_field : filter_linear_mipmap, repeat_disable;
uniform vec2 contact_field_min = vec2(0.0);
uniform vec2 contact_field_extent = vec2(1.0);
uniform float canopy_contact_strength = 0.0;
varying vec3 wp;
varying vec3 wn;
float field(vec2 p){return .50+.24*sin(p.x*.91+p.y*.61+2.17)+.17*sin(p.x*2.70-p.y*1.83+.43)+.09*sin(p.x*7.41+p.y*5.07+1.91);}
void vertex(){mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(Nw*NORMAL);MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;}
void fragment(){
 vec3 n=normalize(wn);vec2 p=wp.xz;float local_slope=length(n.xz)/max(abs(n.y),.000001);
 vec4 w=COLOR;
 if(visual_blend>.5)w=texture(visual_weights,(p-world_min)/world_extent);
 w=max(w,vec4(0));w/=max(dot(w,vec4(1)),.000001);
 vec3 grass=vec3(.659,.788,.373);
 vec3 forest=mix(vec3(.40,.63,.33),grass,shared_woodland_ground);
 vec3 jungle=mix(vec3(.27,.61,.43),grass*vec3(.92,1.0,1.03),shared_woodland_ground);
 vec3 arid=vec3(.80,.68,.39);
 vec3 base=w.r*grass+w.g*forest+w.b*jungle+w.a*arid;
 // Broad, very quiet variation replaces photographic soil detail.
 base*=.985+.025*clamp(field(p*.30),0.0,1.0);
 float stone=smoothstep(.25,.72,local_slope);
 base=mix(base,vec3(.659,.718,.804),stone*.85);
 float d=UV2.x;float slope=UV2.y;
 if(use_shore_tile>.5)d=texture(shore_distance_tile,(p-shore_tile_min)/shore_tile_extent).r*shore_distance_cap;
 float v=clamp(field(p),0,1);float width=mix(.11,.40,v)*mix(1.0,.25,smoothstep(.08,.40,slope));
 float sandy=1.0-smoothstep(.23,.60,max(local_slope,slope));float availability=smoothstep(.16,.76,field(p*.65+vec2(5.3,1.7)));
 float beach=(1.0-smoothstep(width*.50,width,d))*sandy*availability*shore_bands;
 float wet=(1.0-smoothstep(mix(.018,.036,v),mix(.034,.061,v),d))*sandy*shore_bands;
 base=mix(base,vec3(.878,.769,.525),beach);
 base=mix(base,vec3(.64,.62,.40),wet*.55);
 float key=dot(n,normalize(vec3(-.55,.74,.39)));
 float lit=smoothstep(.34,.44,key);
 palette_lit=base;
 palette_shade=shade_endpoint(base);
 form_mask=1.0-lit;
 ALBEDO=vec3(1.0);ROUGHNESS=1.0;
}
void light(){
 vec3 c=shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
 // Godot encodes custom-light accumulation on output; supply linear radiance.
    DIFFUSE_LIGHT+=decode(c);
}
