shader_type spatial;
render_mode unshaded, cull_disabled;
// Exact original clipped water footprint and heights. COLOR expresses only
// the old channel-distance color cue, not depth. No displacement or fake shore.
vec3 encode(vec3 c){return mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
vec3 decode(vec3 c){return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c));}
void fragment(){
 vec3 source=encode(COLOR.rgb);
 float channel_edge=clamp((source.g-.486275)/.05765,0.0,1.0);
 vec3 c=mix(vec3(.235,.624,.682),vec3(.196,.608,.710),channel_edge);
 ALBEDO=OUTPUT_IS_SRGB?c:decode(c);
}
