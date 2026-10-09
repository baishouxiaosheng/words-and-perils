shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform vec3 deep_color : source_color = vec3(.12,.38,.44);
uniform vec3 shallow_color : source_color = vec3(.33,.65,.65);
uniform vec3 sky_color : source_color = vec3(.62,.75,.77);
varying vec3 position_world;
void vertex() { position_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
vec3 decode_srgb(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 encode_srgb(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
void fragment() {
 // No vertex displacement or alpha. Stored footprint and sourcelevel are exact.
 // UV.x is real PL depth at each water vertex, interpolated on that sourceface.
 float depth=max(UV.x,0.0);
 float shallow=exp(-depth*8.0);
 vec2 wave=vec2(sin(position_world.x*6.7+position_world.z*3.3+TIME*.65),cos(position_world.z*7.1-position_world.x*2.8+TIME*.51))*.025;
 vec3 wn=normalize(vec3(wave.x,1.0,wave.y));
 vec3 nv=normalize((VIEW_MATRIX*vec4(wn,0.0)).xyz);
 float fresnel=pow(1.0-clamp(dot(nv,VIEW),0.0,1.0),4.0);
 vec3 dc=deep_color;vec3 sc=shallow_color;vec3 sky=sky_color;
 if (OUTPUT_IS_SRGB) {dc=decode_srgb(dc);sc=decode_srgb(sc);sky=decode_srgb(sky);}
 ALBEDO=mix(mix(dc,sc,shallow*.68),sky,fresnel*.28);
 if (OUTPUT_IS_SRGB) ALBEDO=encode_srgb(ALBEDO);
 NORMAL=nv;
 ROUGHNESS=.32+shallow*.10; SPECULAR=.42; METALLIC=0.0;
}
