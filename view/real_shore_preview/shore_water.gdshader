shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D shore_field : filter_linear, repeat_disable;
uniform vec2 bounds_min;
uniform vec2 bounds_extent;
uniform float distance_cap=1.5;
uniform float bands_enabled=1.0;
uniform float ocean=1.0;
varying vec3 wp;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 // UV.x is exact source level - the same face's interpolated designed_height.
 // Opaque, no discard, no displacement. Only actual source polygons draw water.
 float depth=max(UV.x,0.0);vec4 sf=texture(shore_field,(wp.xz-bounds_min)/bounds_extent);vec2 guv=(wp.xz-bounds_min)/bounds_extent;float within=step(0.0,guv.x)*step(0.0,guv.y)*step(guv.x,1.0)*step(guv.y,1.0);float d=mix(distance_cap,sf.r*distance_cap,within);
 vec3 deep=decode(mix(vec3(.23,.42,.43),vec3(.12,.38,.48),ocean));
 vec3 shallow=decode(mix(vec3(.47,.66,.57),vec3(.40,.72,.70),ocean));
 float shallow_t=exp(-depth*mix(22.0,9.0,ocean))*(.62+.38*exp(-d*1.9));
 vec3 improved=mix(deep,shallow,shallow_t);
 // Narrow discontinuous foam on steep actual ocean shore only, absent on lakes.
 float cliff=smoothstep(.26,.65,sf.g*2.0);float stripes=.5+.5*sin(wp.x*23.1+wp.z*17.3+sin(wp.z*5.7));
 float broken=smoothstep(.43,.78,.5+.5*sin(wp.x*4.7-wp.z*3.3));
 float foam=(1.0-smoothstep(.018,.06,d))*cliff*ocean*broken*(.30+.36*stripes)*within;
 improved=mix(improved,decode(vec3(.83,.86,.79)),foam);
 vec3 olddeep=decode(mix(vec3(.20,.47,.47),vec3(.16,.42,.49),ocean));
 vec3 oldshallow=decode(mix(vec3(.50,.74,.68),vec3(.47,.72,.71),ocean));
 vec3 base=mix(olddeep,oldshallow,exp(-depth*8.0)*.68);
 ALBEDO=mix(base,improved,bands_enabled);
 if(OUTPUT_IS_SRGB)ALBEDO=encode(ALBEDO);
 vec2 wave=vec2(sin(wp.x*6.7+wp.z*3.3),cos(wp.z*7.1-wp.x*2.8))*.017;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(wave.x,1,wave.y)),0)).xyz);
 ROUGHNESS=.58;SPECULAR=.18;METALLIC=0.0;
}
