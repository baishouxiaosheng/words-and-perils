// Independent coverage-AA candidate v1: R6bit continuous union + R2bit domain; GB16 unchanged.
// RECONSTRUCTED SOURCE, not a byte recovery of the missing private shader.
// Godot 4.6.3 target. Source inspection only; not parsed or run in an engine.
// Opaque RGBA8/no-MSAA data target. Alpha is opaque raster coverage; never write ALPHA.
// Data protocol inverse of Godot 4.6.3 GLES3 tonemap_inc.glsl linear_to_srgb.
// Its forward path has no linear toe. Keep this separate from paint palettes.
vec3 data_output_radiance(vec3 c) { return pow((c+vec3(.055))/1.055,vec3(2.4)); }
vec3 saturated(vec3 c,float strength){
 float luma=dot(c,vec3(.2126,.7152,.0722));
 return clamp(mix(vec3(luma),c,strength),vec3(0.0),vec3(1.0));
}
vec3 shade_endpoint(vec3 base) { return saturated(base,1.20)*.60; }
varying vec3 palette_lit;
varying vec3 palette_shade;
varying float form_mask;
varying float mask_depth_16;
vec3 packed_mask_data(float union_mask, float depth_16) {
 float coverage_level=floor(clamp(union_mask,0.0,1.0)*63.0+.5);
 float red_byte=4.0*coverage_level+WP_MASK_DOMAIN;
 float high_byte=floor(depth_16/256.0);
 float low_byte=depth_16-high_byte*256.0;
 return vec3(red_byte,high_byte,low_byte)/255.0;
}
