shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
uniform float shore_bands=1.0;
uniform float river_surface=0.0;
uniform bool ripple_antialiasing=true;
uniform float wave_speed=.16;
varying vec3 wp;
varying vec3 wn;
// Integral of one periodic narrow stripe. Its duty matches the old sinusoidal
// highlight's average (0.04886327), avoiding brighter/wider distant water.
float ripple_integral(float cycle){
 const float duty=0.04886327;
 return floor(cycle)*duty+clamp(fract(cycle)-(.5-duty*.5),0.0,duty);
}
float filtered_ripple(float phase){
 float original=smoothstep(.975,1.0,sin(phase));
 // Differentiate continuous phase BEFORE fract, so seams do not create spikes.
 float cycle=phase/6.28318530718+.25;
 float footprint=max(fwidth(cycle),.00001);
 float coverage=clamp((ripple_integral(cycle+footprint*.5)-ripple_integral(cycle-footprint*.5))/footprint,0.0,1.0);
 // Keep the original profile when resolved; integrate only subpixel detail.
 float resolved=mix(original,coverage,smoothstep(.01,.04,footprint));
 return mix(resolved,.04886327,smoothstep(.5,1.0,footprint));
}
// One shore wave: a thin foam crest born about .26 offshore that rolls in on the
// shore-distance field, widens as it shoals and fades out before it lands.
// Driven only by the mesh's own shore distance, so any generated coast gets it.
float wave_crest(float d, float aa, float travel){
 float at=mix(.26,.015,travel);
 float w=mix(.006,.016,travel);
 float line=1.0-smoothstep(w-aa,w+aa,abs(d-at));
 return line*smoothstep(0.0,.2,travel)*(1.0-smoothstep(.7,1.0,travel));
}
void vertex(){mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(Nw*NORMAL);MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;}
void fragment(){
 float depth=max(UV.x,0.0);float d=UV2.x;float ocean=COLOR.r;
 float shallows=exp(-depth*mix(22.0,9.0,ocean))*(.62+.38*exp(-d*1.9));
 shallows=mix(shallows,.72,river_surface);
 vec3 deep=mix(vec3(.19,.53,.63),vec3(.196,.608,.710),ocean);
 vec3 shallow=vec3(.392,.788,.792);
 vec3 c=mix(deep,shallow,shallows);
 float cliff=smoothstep(.26,.65,UV2.y);float broken=smoothstep(.40,.77,.5+.5*sin(wp.x*4.7-wp.z*3.3));
 float foam=(1.0-smoothstep(.018,.06,d))*cliff*ocean*broken*shore_bands*(1.0-river_surface);
 c=mix(c,vec3(.84,.95,.89),foam*.58);
 // Shore waves on the open sea only. Two staggered crests plus a lapping line;
 // a cheap world-space field breaks them along the coast. Skipped offshore and
 // faded out once a crest is under about a pixel (overview zoom), so it never
 // shimmers and costs nothing on deep water.
 // Derivative is taken before the branch; it is undefined inside divergent flow.
 float wave_aa=max(fwidth(d),.0012);
 if(d<.32 && ocean*(1.0-river_surface)*shore_bands>.01){
  float aa=wave_aa;
  float visible=1.0-smoothstep(.006,.02,aa);
  float t=TIME*wave_speed;
  float along=wp.x*3.1+wp.z*2.2+sin(wp.z*1.4-wp.x*.9)*2.4;
  float crest=wave_crest(d,aa,fract(t))*smoothstep(.40,.70,.5+.5*sin(along));
  crest=max(crest,wave_crest(d,aa,fract(t+.5))*smoothstep(.40,.70,.5+.5*sin(along+2.6)));
  float lap_at=.010+.008*(.5+.5*sin(TIME*1.1+(wp.x-wp.z)*.9));
  float lap=1.0-smoothstep(lap_at-aa,lap_at+aa,d);
  float wave=max(crest,lap*.8)*visible*ocean*(1.0-river_surface)*shore_bands;
  c=mix(c,vec3(.90,.97,.94),wave*.85);
 }
 // Static sparse graphic ripples. No SSR/refraction or per-frame water simulation.
 float phase=wp.x*7.1+wp.z*10.3;
 float stripe=filtered_ripple(phase);
 if(!ripple_antialiasing)stripe=smoothstep(.975,1.0,sin(phase));
 float ripple_patch=smoothstep(.35,.75,.5+.5*sin(wp.x*1.1-wp.z*.81));
 c=mix(c,c+vec3(.045,.055,.035),stripe*ripple_patch*.40);
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

