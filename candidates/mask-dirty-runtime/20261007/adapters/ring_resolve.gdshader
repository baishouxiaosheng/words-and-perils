shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Independent STATIC prototype only: no Main integration or dynamic validation.
// Godot 4.6.3 target; source inspected, not engine parsed or rendered.
// Input: the verified same-raster RGBA8 mask, R6 coverage + R2 domain,
// GB16 depth, A255 on receivers. No source_color, mipmaps or filtered sampling.
// Output: RGB bytes unchanged; A becomes CONDITIONAL inner-ring weight.
// Resolved alpha is NEVER raster validity, union coverage or an outer shadow band.
uniform sampler2D source_mask : filter_nearest, repeat_disable;
uniform bool receiver_mask_valid=false;
uniform bool ring_resolve_enabled=false;
uniform float camera_depth_span=1.0;

vec3 mask_bytes(vec4 value) {
 return round(clamp(value.rgb,vec3(0.0),vec3(1.0))*255.0);
}
float mask_depth(vec3 bytes_value) {
 return (bytes_value.g*256.0+bytes_value.b)/65535.0;
}
float depth_tolerance() {
 return max(2.0/65535.0,.015/max(camera_depth_span,.000001));
}
bool raw_ground_matches(vec4 value,float predicted_depth) {
 vec3 bytes_value=mask_bytes(value);
 // Domain 0/3, water, absent raster coverage and unrelated depth all reject.
 return value.a>=.5 && mod(bytes_value.r,4.0)==1.0 &&
        abs(mask_depth(bytes_value)-predicted_depth)<=depth_tolerance();
}
float neighbor_union_or_neutral(vec2 center_uv,vec2 texel_uv,
                               float center_depth,vec2 depth_gradient,vec2 offset) {
 vec2 sample_uv=center_uv+offset*texel_uv;
 if(any(lessThan(sample_uv,vec2(0.0))) || any(greaterThan(sample_uv,vec2(1.0)))) return 1.0;
 vec4 value=textureLod(source_mask,sample_uv,0.0);
 float predicted_depth=center_depth+dot(depth_gradient,offset);
 if(!raw_ground_matches(value,predicted_depth)) return 1.0;
 return floor(mask_bytes(value).r/4.0)/63.0;
}
void fragment() {
 vec4 center_value=textureLod(source_mask,UV,0.0);
 vec3 center_bytes=mask_bytes(center_value);
 float center_depth=mask_depth(center_bytes);
 vec2 texel_uv=1.0/vec2(textureSize(source_mask,0));

 // Differentiate the DECODED sampled depth at the SAME UV as all neighbors.
 // Invert the canvas UV Jacobian, then convert UV slope to one-mask-texel slope.
 // This keeps a flipped canvas UV axis from reversing the depth prediction.
 vec2 uv_dx=dFdx(UV);
 vec2 uv_dy=dFdy(UV);
 float depth_dx=dFdx(center_depth);
 float depth_dy=dFdy(center_depth);
 float uv_det=uv_dx.x*uv_dy.y-uv_dx.y*uv_dy.x;
 float safe_det=abs(uv_det)>1e-20 ? uv_det : 1.0;
 vec2 depth_gradient=vec2(depth_dx*uv_dy.y-depth_dy*uv_dx.y,
                          uv_dx.x*depth_dy-uv_dy.x*depth_dx)/safe_det*texel_uv;

 bool center_in_view=all(greaterThanEqual(UV,vec2(0.0))) && all(lessThanEqual(UV,vec2(1.0)));
 bool center_valid=center_in_view && raw_ground_matches(center_value,center_depth);
 float eroded=center_valid ? floor(center_bytes.r/4.0)/63.0 : 1.0;
 // Full radius-4 integer disk: x*x+y*y<=16, exactly 49 taps INCLUDING center.
 // Reuse the already-read center, then sample all 48 other disk points once.
 // Bounds/loop decisions are uniform. No pixel-specific exit before fwidth.
 for(int y=-4;y<=4;y++) {
  for(int x=-4;x<=4;x++) {
   if(x*x+y*y<=16 && (x!=0 || y!=0)) {
    eroded=min(eroded,neighbor_union_or_neutral(UV,texel_uv,center_depth,
                                               depth_gradient,vec2(float(x),float(y))));
   }
  }
 }
 // About one pixel at the INNER boundary; retain the R6 quantization floor.
 float inner_aa=clamp(.5*fwidth(eroded),1.0/63.0,.5);
 float ring_weight=1.0-smoothstep(.5-inner_aa,.5+inner_aa,eroded);
 bool enabled=ring_resolve_enabled && receiver_mask_valid && camera_depth_span>0.0 && abs(uv_det)>1e-20;
 // Keep even invalid/background RGB byte-for-byte. Alpha alone is the new payload.
 COLOR=vec4(center_bytes/255.0,(enabled && center_valid) ? ring_weight : 0.0);
}

// Bind a separate RGBA8/no-MSAA canvas target at the exact source-mask raster.
// Draw full-viewport with same-raster UV; do not read/write the same attachment.
// Preserve data bytes: no color conversion, modulation, tonemapping or post FX.
// Clear RGB domain 0 remains identifiable after alpha is repurposed.
// Coplanar same-domain objects remain indistinguishable; depth is not object ID.
// Quantized depth derivatives can cross silhouettes or domain/depth discontinuities:
// affected neighbors reject to neutral 1; no tolerance expansion is used here.
