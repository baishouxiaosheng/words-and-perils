// Independent STATIC precomputed-ring prototype: no Main/dynamic integration.
// RECONSTRUCTED SOURCE; not recovery of the missing private shader bytes.
// Godot 4.6.3 target. Source inspected only; not engine parsed/native validated.
// Include in the unchanged color adapter. Bind COMPLETED resolved mask, not raw.
// RGB retains R6 union + R2 domain and GB16 depth. A is conditional ring weight.
// Alpha 0 is valid deep-interior data; alpha must NEVER be used as coverage/validity.
uniform int shadow_debug=0;
uniform bool receiver_ring_enabled=false;
uniform bool receiver_contour_aa_enabled=false;
uniform bool receiver_mask_valid=false;
uniform sampler2D receiver_mask : filter_nearest, repeat_disable;
uniform float camera_depth_span=1.0;
vec3 decode(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 saturated(vec3 c,float strength){
 float luma=dot(c,vec3(.2126,.7152,.0722));
 return clamp(mix(vec3(luma),c,strength),vec3(0.0),vec3(1.0));
}
vec3 shade_endpoint(vec3 base) { return saturated(base,1.20)*.60; }
varying vec3 palette_lit;
varying vec3 palette_shade;
varying float form_mask;
// Assigned by the unchanged fragment capture; light reads only varyings.
varying vec2 receiver_screen_uv;
varying float receiver_fragdepth;
varying vec2 receiver_depth_gradient;
varying vec2 receiver_texel_uv;
varying float receiver_mask_raster_match;
float receiver_depth_tolerance() {
 return max(2.0/65535.0,.015/max(camera_depth_span,.000001));
}
vec3 receiver_bytes(vec4 sample_value) {
 return round(clamp(sample_value.rgb,vec3(0.0),vec3(1.0))*255.0);
}
float receiver_union_coverage(vec3 bytes_value) {
 return floor(bytes_value.r/4.0)/63.0;
}
bool receiver_matches(vec4 sample_value,float predicted_depth) {
 if(camera_depth_span<=0.0) return false;
 vec3 bytes_value=receiver_bytes(sample_value);
 float domain=mod(bytes_value.r,4.0);
 // Explicitly reject domain 0/3; resolved alpha has no validity semantics.
 if((domain!=1.0 && domain!=2.0) || abs(domain-WP_RECEIVER_DOMAIN)>.1) return false;
 float depth=(bytes_value.g*256.0+bytes_value.b)/65535.0;
 return abs(depth-predicted_depth)<=receiver_depth_tolerance();
}
// Union, validity, conditional ring alpha. Invalid filter centers are skipped.
vec3 receiver_union_sample(vec2 pixel_offset) {
 vec2 sample_uv=receiver_screen_uv+pixel_offset*receiver_texel_uv;
 if(sample_uv.x<0.0 || sample_uv.x>1.0 || sample_uv.y<0.0 || sample_uv.y>1.0) return vec3(1.0,0.0,0.0);
 vec4 sample_value=textureLod(receiver_mask,sample_uv,0.0);
 float predicted_depth=receiver_fragdepth+dot(receiver_depth_gradient,pixel_offset);
 if(!receiver_matches(sample_value,predicted_depth)) return vec3(1.0,0.0,0.0);
 return vec3(receiver_union_coverage(receiver_bytes(sample_value)),1.0,clamp(sample_value.a,0.0,1.0));
}
vec3 receiver_coverage_band(vec3 raw_sample) {
 float aa=clamp(.5*fwidth(raw_sample.x),1.0/63.0,.5);
 float band=smoothstep(.5-aa,.5+aa,raw_sample.x);
 return vec3(band,raw_sample.y,raw_sample.z);
}
vec2 receiver_filtered_band_ring(float fallback_band) {
 // Exactly five cross samples: continuous union AA ONLY at the outer band.
 // All fwidth calls precede pixel-specific guards; no nonuniform derivative exit.
 vec3 center=receiver_coverage_band(receiver_union_sample(vec2(0.0,0.0)));
 vec3 left=receiver_coverage_band(receiver_union_sample(vec2(-1.0,0.0)));
 vec3 right=receiver_coverage_band(receiver_union_sample(vec2(1.0,0.0)));
 vec3 up=receiver_coverage_band(receiver_union_sample(vec2(0.0,-1.0)));
 vec3 down=receiver_coverage_band(receiver_union_sample(vec2(0.0,1.0)));
 if(receiver_mask_raster_match<.5 || center.y<.5) return vec2(fallback_band,0.0);
 float weight_sum=.5*center.y+.125*(left.y+right.y+up.y+down.y);
 float band_sum=.5*center.x*center.y+.125*(left.x*left.y+right.x*right.y+up.x*up.y+down.x*down.y);
 if(weight_sum<=0.0) return vec2(fallback_band,0.0);
 float band=clamp(band_sum/weight_sum,0.0,1.0);
 // Saturated ring is NOT cross-averaged. Center alpha is a conditional ratio.
 // Center threshold AA confines ring to the original union contour: cross band
 // may soften ordinary shade outside it, but must not paint green on lit pixels.
 float ring_weight=min(band,center.x*center.z);
 return vec2(band,ring_weight);
}
vec3 receiver_ring_endpoint(vec3 lit,vec3 shade) {
 vec3 ring=saturated(shade,1.65);
 vec3 weights=vec3(.2126,.7152,.0722);
 float lit_luma=max(dot(lit,weights),0.0);
 float ring_luma=max(dot(ring,weights),.000001);
 ring*=min(1.0,lit_luma/ring_luma);
 return clamp(ring,vec3(0.0),vec3(1.0));
}
vec3 shade_once(vec3 lit,vec3 shade,float form,float cast) {
 // Preserve original palette/form/cast union and choose the shade endpoint once.
 float mask=clamp(max(form,cast),0.0,1.0);
 if(shadow_debug==1) return vec3(form,cast,mask);
 if(shadow_debug==2) return vec3(1.0-cast);
 if(shadow_debug==3) return vec3(form);
 float aa=clamp(max(fwidth(mask),.0039215686)*.50,.0039215686,.020);
 float two_band=smoothstep(.5-aa,.5+aa,mask);
 // Uniform gates preserve default-off baseline. Water never gets a ring.
 if(!receiver_ring_enabled || !receiver_contour_aa_enabled || !receiver_mask_valid || WP_RECEIVER_DOMAIN!=1.0) {
  return clamp(mix(lit,shade,two_band),vec3(0.0),vec3(1.0));
 }
 float coverage_aa=clamp(.5*fwidth(mask),1.0/63.0,.5);
 float fallback_band=smoothstep(.5-coverage_aa,.5+coverage_aa,mask);
 vec2 band_ring=receiver_filtered_band_ring(fallback_band);
 vec3 result=lit*(1.0-band_ring.x)+shade*(band_ring.x-band_ring.y)+receiver_ring_endpoint(lit,shade)*band_ring.y;
 return clamp(result,vec3(0.0),vec3(1.0));
}
// External binding only; no pass framework, raw/shape/camera/Main edits here.
// Resolve the original mask first, then bind its separate same-raster RGBA8 output.
// Same orthographic view/span/geometry, no MSAA/color conversion/modulation/post FX.
// Raw nearest/no-mip/no-source_color sampling; RGB retains exact original bytes.
// Set valid + both color gates only after a completed resolve with positive span.
// Clear RGB domain 0, unknown 3 and unrelated depth reject even when A is nonzero.
// Domain+GB16 is not object ID: coplanar same-domain isolation is still external.
