shader_type spatial;
render_mode unshaded, cull_disabled;
// Generated macro v2 only. COLOR is the exact source linear palette;
// UV2.x = soil, UV2.y = alpine. No source mask, height or normal mutation.
uniform int surface_kind = 0; // 0 land, 1 bank, 2 cutaway skirt
varying vec3 world_normal;
vec3 encode(vec3 c) {return mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
vec3 decode(vec3 c) {return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void vertex(){world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 n=normalize(world_normal);
 // The source emits double-sided ground; orient its existing normal as the
 // original macro material did, including back-facing top triangles.
 if(!FRONT_FACING)n=-n;
 vec3 source=encode(COLOR.rgb);
 float soil=clamp(UV2.x,0.0,1.0);
 // Invert only the existing source palette's jungle blend, not world height.
 vec3 meadow_source=mix(vec3(.454902,.607843,.313725),vec3(.788235,.678431,.482353),soil);
 float jungle=clamp((meadow_source.g-source.g)/max(meadow_source.g-.466667,.001),0.0,1.0);
 vec3 base=mix(vec3(.655,.784,.388),vec3(.867,.745,.510),soil);
 base=mix(base,vec3(.337,.596,.416),jungle);
 // Plateau caps retain their true biome; only actual scarps/exposed alpine rock.
 float slope=1.0-abs(n.y);
 float rock=max(smoothstep(.17,.55,slope),clamp(UV2.y,0.0,1.0));
 vec3 stone=mix(vec3(.647,.690,.761),vec3(.757,.667,.525),soil*.72);
 base=mix(base,stone,rock);
 if(surface_kind==1){
  float dry=clamp((source.r-.40)/.29,0.0,1.0);
  base=mix(vec3(.40,.55,.47),vec3(.765,.686,.478),dry);
 }
 if(surface_kind==2)base=vec3(.48,.58,.51);
 float key=dot(n,normalize(vec3(-.55,.74,.39)));
 // The macro source has dense genuine facets. A modest transition keeps
 // the two broad light groups without turning tiny normal changes into
 // a binary staircase on the ridge. It does not blur framebuffer pixels.
 float lit=smoothstep(.24,.44,key);
 vec3 c=mix(base*vec3(.70,.80,.90),base,lit);
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
