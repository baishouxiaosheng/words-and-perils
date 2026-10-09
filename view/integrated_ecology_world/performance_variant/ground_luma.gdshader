shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Independent visual materials. Weights do not change source ecology support.
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_baked_luminance = 0.0;
uniform sampler2D soil_luminance : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_luminance : filter_linear_mipmap, repeat_enable;
uniform float shared_woodland_ground = 1.0;
uniform float shore_bands = 1.0;
uniform float visual_blend = 0.0;
uniform sampler2D visual_weights : filter_linear, repeat_disable;
uniform vec2 world_min = vec2(-44.1673,-38.5);
uniform vec2 world_extent = vec2(88.3346,77.0);
varying vec3 wp;
varying vec3 wn;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
float field(vec2 p){return .50+.24*sin(p.x*.91+p.y*.61+2.17)+.17*sin(p.x*2.70-p.y*1.83+.43)+.09*sin(p.x*7.41+p.y*5.07+1.91);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 n=normalize(wn);vec2 p=wp.xz;float local_slope=length(n.xz)/max(abs(n.y),.000001);
 float soil_l;float rock_l;
 if(use_baked_luminance>.5){
  soil_l=texture(soil_luminance,p/1.8).r;rock_l=texture(rock_luminance,p/1.1).r;
 }else{
  vec3 soil=texture(soil_albedo,p/1.8).rgb;vec3 rocktex=texture(rock_albedo,p/1.1).rgb;
  if(OUTPUT_IS_SRGB){soil=decode(soil);rocktex=decode(rocktex);}
  soil_l=dot(soil,vec3(.2126,.7152,.0722));rock_l=dot(rocktex,vec3(.2126,.7152,.0722));
 }
 float detail=clamp(.83+soil_l*.8,.84,1.13);float rock_detail=clamp(.85+rock_l*.55,.87,1.12);
 // Original source dry weights, reduced to four visual soil classes only.
 vec4 w=COLOR;
 if(visual_blend>.5){vec2 guv=(p-world_min)/world_extent;w=texture(visual_weights,guv);}
 w=max(w,vec4(0));w/=max(dot(w,vec4(1)),.000001);
 vec3 grass=decode(vec3(.53,.62,.31));
 vec3 forest=mix(decode(vec3(.29,.43,.24)),grass,shared_woodland_ground);
 vec3 jungle=mix(decode(vec3(.20,.39,.28)),grass*vec3(.95,1.02,.99),shared_woodland_ground);
 vec3 arid=decode(vec3(.67,.58,.35));
 vec3 base=(w.r*grass+w.g*forest+w.b*jungle+w.a*arid)*detail;
 vec2 layer=UV;
 if(visual_blend>.5)layer.y=.03+.62*w.a;
 // Area-weighted source-node normals interpolate continuously across source face edges.
 // Raw source rock labels are diagnostic, never a whole-face grey paint switch.
 float stone=smoothstep(.24,.68,local_slope);float sand=clamp(layer.y,0,1);
 base=mix(base,decode(vec3(.59,.58,.51))*rock_detail,stone*.45);
 base=mix(base,decode(vec3(.66,.57,.36))*detail,sand*.11);
 // Actual source shore distance and slope; no coordinate warp, water expansion or desert reclassification.
 float d=UV2.x;float slope=UV2.y;
 float v=clamp(field(p),0,1);float width=mix(.11,.40,v)*mix(1.0,.25,smoothstep(.08,.40,slope));
 float sandy=1.0-smoothstep(.23,.60,max(local_slope,slope));float availability=smoothstep(.16,.76,field(p*.65+vec2(5.3,1.7)));
 float beach=(1.0-smoothstep(width*.50,width,d))*sandy*availability*shore_bands;
 float wet=(1.0-smoothstep(mix(.018,.036,v),mix(.034,.061,v),d))*sandy*shore_bands;
 float fine=.96+.04*sin(p.x*68.1+sin(p.y*23.7))*sin(p.y*61.7-p.x*5.1);
 base=mix(base,decode(vec3(.70,.64,.45))*fine,beach);
 ALBEDO=mix(base,decode(vec3(.43,.40,.28)),wet*.55);
 if(OUTPUT_IS_SRGB)ALBEDO=encode(ALBEDO);
 ROUGHNESS=mix(.89,.73,wet);SPECULAR=.21;METALLIC=0.0;
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0)).xyz);
}
