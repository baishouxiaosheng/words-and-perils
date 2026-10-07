shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
// RECONSTRUCTED specialization of frozen v5 water; not missing-source byte recovery.
// This compile-time data branch is isolated from the default-off color adapters.
#define WP_MASK_DATA_PASS
#define WP_MASK_DOMAIN 2.0
#include "mask_data_interface.gdshaderinc"
uniform float shore_bands=1.0;
uniform float river_surface=0.0;
uniform bool ripple_antialiasing=true;
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
 // Static sparse graphic ripples. No SSR/refraction or per-frame water simulation.
 float phase=wp.x*7.1+wp.z*10.3;
 float stripe=filtered_ripple(phase);
 if(!ripple_antialiasing)stripe=smoothstep(.975,1.0,sin(phase));
 float ripple_patch=smoothstep(.35,.75,.5+.5*sin(wp.x*1.1-wp.z*.81));
 c=mix(c,c+vec3(.045,.055,.035),stripe*ripple_patch*.40);
 palette_lit=c;palette_shade=shade_endpoint(c);
 form_mask=1.0-smoothstep(.20,.30,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
 // Capture raster depth in fragment; light must not read FRAGCOORD.
 mask_depth_16=round(clamp(FRAGCOORD.z,0.0,1.0)*65535.0);
 ALBEDO=vec3(1.0);ROUGHNESS=1.0;
}

void light(){
#ifdef WP_MASK_DATA_PASS
 // Union form/cast once before thresholding; opaque raster coverage supplies alpha.
 vec3 data=packed_mask_data(max(form_mask,1.0-ATTENUATION),mask_depth_16);
 // Preserve the original engine sRGB output path by supplying decoded radiance.
 DIFFUSE_LIGHT+=data_output_radiance(data);
#endif
}
