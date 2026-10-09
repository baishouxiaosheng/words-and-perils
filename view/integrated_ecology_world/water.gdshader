shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform float shore_bands = 1.0;
varying vec3 wp;
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 float depth=max(UV.x,0);float d=UV2.x;float slope=UV2.y;float ocean=COLOR.r;
 vec3 deep=decode(mix(vec3(.23,.42,.43),vec3(.12,.38,.48),ocean));
 vec3 shallow=decode(mix(vec3(.47,.66,.57),vec3(.40,.72,.70),ocean));
 float shallow_t=exp(-depth*mix(22,9,ocean))*(.62+.38*exp(-d*1.9));
 vec3 water=mix(deep,shallow,shallow_t);
 float cliff=smoothstep(.26,.65,slope);float stripes=.5+.5*sin(wp.x*23.1+wp.z*17.3+sin(wp.z*5.7));float broken=smoothstep(.43,.78,.5+.5*sin(wp.x*4.7-wp.z*3.3));
 float foam=(1.0-smoothstep(.018,.06,d))*cliff*ocean*broken*(.30+.36*stripes)*shore_bands;
 ALBEDO=mix(water,decode(vec3(.83,.86,.79)),foam);
 if(OUTPUT_IS_SRGB)ALBEDO=encode(ALBEDO);
 vec2 wave=vec2(sin(wp.x*6.7+wp.z*3.3),cos(wp.z*7.1-wp.x*2.8))*.013;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(wave.x,1,wave.y)),0)).xyz);
 ROUGHNESS=.63;SPECULAR=.16;METALLIC=0.0;
}
