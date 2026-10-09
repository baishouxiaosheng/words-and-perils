shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_patch = 2.8;
// Independent visual-only B1/B2 switches. Source ecology/ownership does not change.
uniform float woodland_ground_shared = 0.0;
uniform float zone_visual_blend = 0.0;
uniform float zone_visual_organic = 0.0;
uniform sampler2D ground_organic_weights_a : filter_linear, repeat_disable;
uniform sampler2D ground_organic_weights_b : filter_linear, repeat_disable;
uniform sampler2D ground_pure_weights_a : filter_linear, repeat_disable;
uniform sampler2D ground_pure_weights_b : filter_linear, repeat_disable;
uniform sampler2D ground_blend_weights_a : filter_linear, repeat_disable;
uniform sampler2D ground_blend_weights_b : filter_linear, repeat_disable;
uniform sampler2D canopy_material_ao : filter_linear, repeat_disable;
uniform vec2 ground_bounds_min = vec2(0.0);
uniform vec2 ground_extent = vec2(1.0);
uniform vec3 palette_arid = vec3(.42,.25,.08);
uniform vec3 palette_cold_open = vec3(.34,.36,.32);
uniform vec3 palette_forest = vec3(.065,.21,.075);
uniform vec3 palette_grass = vec3(.20,.38,.08);
uniform vec3 palette_jungle = vec3(.025,.13,.06);
uniform vec3 palette_wetland = vec3(.12,.27,.15);
varying vec3 position_world;
varying vec3 normal_world;
void vertex() {
 position_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
vec3 decode_srgb(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 encode_srgb(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
void fragment() {
 vec3 n=normalize(normal_world);
 vec2 uv=position_world.xz/texture_patch;
 vec3 soil=texture(soil_albedo,uv).rgb;
 vec3 rock=texture(rock_albedo,uv).rgb;
 if (OUTPUT_IS_SRGB) {soil=decode_srgb(soil);rock=decode_srgb(rock);}
 // Forward+/Mobile texture source_color performs the decode.
 // Compatibility samples sRGB and decodes ALBEDO after custom fragment().
 // Vertex ecology palette is linear. Detail modulates luminance, not class.
 float sl=dot(soil,vec3(.2126,.7152,.0722));
 float rl=dot(rock,vec3(.2126,.7152,.0722));
 float soil_detail=clamp(.83+sl*.8,.84,1.13);
 float rock_detail=clamp(.85+rl*.55,.87,1.12);
 float stone=clamp(UV.x,0.0,1.0);
 float sand=clamp(UV.y,0.0,1.0);
 vec3 ground=COLOR.rgb;
 if (woodland_ground_shared>0.5 || zone_visual_blend>0.5) {
  vec2 guv=clamp((position_world.xz-ground_bounds_min)/max(ground_extent,vec2(.0001)),vec2(0.0),vec2(1.0));
  vec4 wa;
  vec4 wb;
  if (zone_visual_blend>0.5) {
   if (zone_visual_organic>0.5) {
    wa=texture(ground_organic_weights_a,guv);wb=texture(ground_organic_weights_b,guv);
   } else {
    wa=texture(ground_blend_weights_a,guv);wb=texture(ground_blend_weights_b,guv);
   }
  } else {
   wa=texture(ground_pure_weights_a,guv);
   wb=texture(ground_pure_weights_b,guv);
  }
  // Weights are raw data, not sRGB colors. Renormalization handles RGBA8/filtering.
  float total=max(dot(wa,vec4(1.0))+wb.r+wb.g,.000001);
  wa/=total;wb/=total;
  vec3 woodland=woodland_ground_shared>0.5?palette_grass:palette_forest;
  vec3 tropical=woodland_ground_shared>0.5?palette_grass:palette_jungle;
  ground=wa.r*palette_arid+wa.g*palette_cold_open+wa.b*woodland+wa.a*palette_grass+wb.r*tropical+wb.g*palette_wetland;
  if (zone_visual_blend>0.5) {
   // The same weights blend local sand/soil; palette-only mixing left a hard arid seam.
   // Exposed rock stays original face-slope detail. Raw source UV/masks are untouched.
   sand=(1.0-stone)*mix(.03,.65,wa.r);
  }
  if (woodland_ground_shared>0.5) {
   // Crown-footprint material AO proxy, bounded to 16%; never a dark whole-hex coat.
   ground*=1.0-.16*texture(canopy_material_ao,guv).r;
  }
 }
 vec3 rock_tint=vec3(.29,.285,.255)*rock_detail;
 vec3 sand_tint=vec3(.49,.355,.18)*soil_detail;
 ALBEDO=clamp(ground*soil_detail*(1.0-stone-sand)+rock_tint*stone+sand_tint*sand,vec3(.012),vec3(.68));
 if (OUTPUT_IS_SRGB) ALBEDO=encode_srgb(ALBEDO);
 ROUGHNESS=.88; SPECULAR=.24; METALLIC=0.0;
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
