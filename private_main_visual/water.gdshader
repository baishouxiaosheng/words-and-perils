shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
uniform float shore_bands=1.0;
uniform float river_surface=0.0;
uniform float wave_speed=.07;
// One seamless noise tile (water_noise.tres). Every swell and foam pattern is
// a few mipmapped reads of it at different scales; nothing is simulated.
uniform sampler2D water_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
varying vec3 wn;
float tile(vec2 p){return texture(water_noise,p).r;}
// Swell height for the open-water bands: a slow warp, a broad layer and a finer
// one drifting the other way.
float swell(vec2 s, float t){
 float warp=texture(water_noise,s*.05+t*vec2(.020,.007)).r;
 return texture(water_noise,s*.11+vec2(warp*.35,0.0)+t*vec2(.012,.004)).r*.65+texture(water_noise,s*.23+vec2(.37,.11)-t*vec2(.010,.006)).r*.35;
}
// A threshold with a pixel-wide edge.
float edge(float x, float at){float w=max(fwidth(x),.001);return smoothstep(at-w,at+w,x);}
// Foam where a shape outweighs noise: its ends and borders dissolve into lace
// instead of stopping on a cut.
float foam(float shape, float noise){return edge(shape-noise,0.0);}
void vertex(){mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(Nw*NORMAL);MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;}
void fragment(){
 float depth=max(UV.x,0.0);float d=UV2.x;float ocean=COLOR.r;
 float shallows=exp(-depth*mix(22.0,9.0,ocean))*(.62+.38*exp(-d*1.9));
 shallows=mix(shallows,.72,river_surface);
 vec3 deep=mix(vec3(.19,.53,.63),vec3(.196,.608,.710),ocean);
 vec3 shallow=vec3(.392,.788,.792);
 vec3 c=mix(deep,shallow,shallows);
 float cliff=smoothstep(.26,.65,UV2.y);float broken=smoothstep(.40,.77,.5+.5*sin(wp.x*4.7-wp.z*3.3));
 float cliff_foam=(1.0-smoothstep(.018,.06,d))*cliff*ocean*broken*shore_bands*(1.0-river_surface);
 c=mix(c,vec3(.84,.95,.89),cliff_foam*.58);
 float t=TIME*wave_speed;
 vec2 q=wp.xz;
 float pixel=length(fwidth(q));
 float sea=ocean*(1.0-river_surface);

 // Open water, cel-shaded: a swell height (two drifting layers of the tile,
 // stretched along one swell direction) is differentiated across the swell and
 // split into bands, so troughs facing away from the light read as dark blocks
 // and the crests facing it as a light band edged with white. Bands fade before
 // the mipmapped tile blurs toward its mean, so a wide view stays calm.
 vec2 s=vec2(dot(q,vec2(.83,.56)),dot(q,vec2(-.56,.83)))*vec2(.36,1.0);
 vec2 across=vec2(0.0,.22);
 float h0=swell(s-across,t);float h1=swell(s,t);float h2=swell(s+across,t);
 float lit=h2-h0;
 float offshore=sea*smoothstep(.04,.22,d);
 float dark=edge(-lit,.06)*offshore*(1.0-smoothstep(.15,.35,pixel));
 float light=edge(lit,.04)*offshore*(1.0-smoothstep(.10,.25,pixel));
 float white=edge(lit+.06*h1,.21)*offshore*(1.0-smoothstep(.05,.10,pixel));
 c=mix(c,c*vec3(.80,.89,.98),dark*.45);
 c=mix(c,mix(c,vec3(.50,.86,.88),.38),light);
 c=mix(c,vec3(.86,.96,.96),white*.75);

 // Surf on the open sea: two staggered sets roll in on the shore-distance
 // field (world units; the fixed coast's field stops at .45, so the surf zone
 // ends by .42). Each place has its own arrival time (low-frequency noise),
 // each wave a new foam pattern (offset per cycle, switched while it is
 // invisible), and a slow along-shore field decides how much of a crest
 // survives, so fronts arrive out of step and in pieces. A breaking crest drags
 // a widening foam trail; the landing wave pushes a lacy sheet up the beach
 // that thins as it draws back. Faded once a band is under a pixel wide.
 float aa=max(fwidth(d),.002);
 float surf=sea*shore_bands*(1.0-smoothstep(.03,.07,aa))*(1.0-smoothstep(.34,.42,d));
 float spray=0.0;float face=0.0;
 for(int k=0;k<2;k++){
  vec2 o=k==0 ? vec2(0.0) : vec2(17.3,5.1);
  float ta=t+.5*float(k)+tile(q*.09+o)*1.6;
  float travel=fract(ta);
  float at=mix(.40,.02,travel);
  float breaking=smoothstep(.40,.80,travel);
  float half_w=mix(.012,.040,travel);
  float band=1.0-smoothstep(0.0,half_w,abs(d-at));
  float trail=breaking*smoothstep(at+.04+.10*breaking,at,d)*step(at,d)*.75;
  float shape=max(band,trail)*smoothstep(0.0,.2,travel)*(1.0-smoothstep(.85,1.0,travel));
  float survive=.5+.6*smoothstep(.3,.65,tile(q*.05+o+vec2(3.1,9.4)));
  spray=max(spray,foam(shape*survive,.9*tile(q*.9+o+floor(ta)*vec2(.31,.17))));
  face=max(face,smoothstep(at+.14,at+.02,d)*step(at,d)*smoothstep(.1,.5,travel)*(1.0-.6*breaking));
  float landed=fract(ta+.12);
  float run=.02+.09*smoothstep(0.0,.08,landed)*(1.0-smoothstep(.08,.65,landed));
  float sheet=clamp(1.0-d/run,0.0,1.0)*1.15;
  spray=max(spray,foam(sheet,.75*tile(q*1.3+o+vec2(t*.4,0.0))));
  float remnant=(1.0-smoothstep(0.0,.14,d))*(1.0-smoothstep(.1,.9,landed))*.7;
  spray=max(spray,.6*foam(remnant,tile(q*1.9+o+floor(ta)*vec2(.23,.41))));
 }
 c=mix(c,vec3(.40,.84,.82),face*.28*surf);
 c=mix(c,vec3(.93,.98,.97),spray*.9*surf);
 palette_lit=c;palette_shade=shade_endpoint(c);
 form_mask=1.0-smoothstep(.20,.30,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
 ALBEDO=vec3(1.0);ROUGHNESS=1.0;
}

// Water-only projection AA candidate. Original ripple/geometry/palette unchanged.
// Filtered real visibility retains two exact endpoints; threshold footprint is
// approximately one raster pixel instead of the shared .020 scalar cap.
uniform bool water_projection_antialiasing=false;
vec3 shade_water_projection_once(vec3 lit,vec3 shade,float form,float cast){
 float mask=clamp(max(form,cast),0.0,1.0);
 if(shadow_debug==1)return vec3(form,cast,mask);
 if(shadow_debug==2)return vec3(1.0-cast);
 if(shadow_debug==3)return vec3(form);
 float derivative=max(fwidth(mask),1.0/255.0);
 float aa=clamp(.5*derivative,1.0/255.0,.5);
 float two_band=smoothstep(.5-aa,.5+aa,mask);
 vec3 base=mix(lit,shade,two_band);
 // Preserve the original once-unioned coloured narrow contour expression.
 float edge_distance=(mask-.5)/derivative;
 float band=smoothstep(.0,.15,edge_distance)*(1.0-smoothstep(.85,1.25,edge_distance));
 vec3 edge=saturated(shade,1.45);
 return clamp(mix(base,edge,band),vec3(0.0),vec3(1.0));
}
void light(){
 vec3 c=water_projection_antialiasing ? shade_water_projection_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION) : shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
 DIFFUSE_LIGHT+=decode(c);
}

