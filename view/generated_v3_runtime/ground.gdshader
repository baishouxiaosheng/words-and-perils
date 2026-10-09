shader_type spatial;
render_mode unshaded, cull_disabled;
// Opt-in generated v3 only. COLOR is the exact source linear palette;
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
 // Continuous Lambert response for the native averaged normals. The previous
 // narrow smoothstep saturated on almost all upward-facing ground.
 vec3 light_direction=normalize(vec3(-.55,.74,.39));
 float key=max(dot(n,light_direction),0.0);
 // Cool sky fill + warm direct light in linear space. Normalize at an up
 // normal so flat terrain keeps its established palette brightness; facing
 // slopes brighten as well as back slopes darken, without a binary light band.
 vec3 sky_energy=.28*vec3(.78,.87,.95);
 vec3 sun_energy=.90*vec3(1.0,.96,.88);
 vec3 light_energy=(sky_energy+sun_energy*key)/(sky_energy+sun_energy*light_direction.y);
 vec3 c=encode(decode(base)*light_energy);
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
