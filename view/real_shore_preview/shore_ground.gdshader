shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D shore_field : filter_linear, repeat_disable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 bounds_min;
uniform vec2 bounds_extent;
uniform float distance_cap = 1.5;
uniform float bands_enabled = 1.0;
varying vec3 wp;
varying vec3 wn;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
float field(vec2 p){return .50+.24*sin(p.x*.91+p.y*.61+2.17)+.17*sin(p.x*2.70-p.y*1.83+.43)+.09*sin(p.x*7.41+p.y*5.07+1.91);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 n=normalize(wn);vec2 p=wp.xz;vec3 soil=texture(soil_albedo,p/2.8).rgb;vec3 rocktex=texture(rock_albedo,p/1.45).rgb;
 if(OUTPUT_IS_SRGB){soil=decode(soil);rocktex=decode(rocktex);}
 float sl=dot(soil,vec3(.2126,.7152,.0722));float rl=dot(rocktex,vec3(.2126,.7152,.0722));
 float detail=clamp(.83+sl*.8,.84,1.13);float rd=clamp(.85+rl*.55,.87,1.12);
 float rock=clamp(UV.x,0.0,1.0);vec3 base=mix(COLOR.rgb*detail,vec3(.29,.285,.255)*rd,rock);
 vec4 sf=texture(shore_field,(p-bounds_min)/bounds_extent);float d=sf.r*distance_cap;
 float near_slope=sf.g*2.0;float local_slope=length(n.xz)/max(abs(n.y),.000001);
 // Width varies at several world scales. The water zero line is never warped.
 float v=clamp(field(p),0.0,1.0);float width=mix(.11,.40,v)*mix(1.0,.25,smoothstep(.08,.40,near_slope));
 float sandy=1.0-smoothstep(.23,.60,max(local_slope,near_slope));
 vec2 guv=(p-bounds_min)/bounds_extent;float within=step(0.0,guv.x)*step(0.0,guv.y)*step(guv.x,1.0)*step(guv.y,1.0);
 float availability=smoothstep(.16,.76,field(p*.65+vec2(5.3,1.7)));
 float beach=(1.0-smoothstep(width*.50,width,d))*sandy*availability*bands_enabled*within;
 float wet=(1.0-smoothstep(mix(.018,.036,v),mix(.034,.061,v),d))*sandy*bands_enabled*within;
 float fine=.96+.04*sin(p.x*68.1+sin(p.y*23.7))*sin(p.y*61.7-p.x*5.1);
 vec3 sand=decode(vec3(.70,.64,.45))*fine;
 vec3 wet_sand=decode(vec3(.43,.40,.28))*(.97+.03*field(p*3.7));
 vec3 shoreline=mix(base,sand,beach);
 ALBEDO=mix(shoreline,wet_sand,wet*.62);
 if(OUTPUT_IS_SRGB)ALBEDO=encode(ALBEDO);
 ROUGHNESS=mix(.90,.72,wet);SPECULAR=mix(.21,.30,wet);METALLIC=0.0;NORMAL=normalize((VIEW_MATRIX*vec4(n,0)).xyz);
}
