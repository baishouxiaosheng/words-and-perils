shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
uniform float shore_bands=1.0;
uniform float river_surface=0.0;
uniform float wave_speed=.07;
// One seamless noise tile (water_noise.tres) for every warp and breakup mask.
uniform sampler2D water_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_marks : hint_default_black, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
varying vec3 wn;
// Hand-painted water in the cel style: every layer is a binarised mask (a
// threshold with a pixel-wide edge) whose boundary is warped by noise, so the
// result is a few flat colours with painterly edges, never a soft blend.
float tile(vec2 p){return texture(water_noise,p).r;}
// A sharper read for strongly stretched coordinates: the mip follows the
// short axis instead of the long one, so thin shapes stay crisp.
float tile_sharp(vec2 p){return textureGrad(water_noise,p,dFdx(p)*.3,dFdy(p)*.3).r;}
float edge(float x, float at){float w=max(fwidth(x),.001);return smoothstep(at-w,at+w,x);}
vec2 cell_hash(vec2 p){p=vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)));return fract(sin(p)*43758.5453);}
// Distance to the nearest and second-nearest wandering Voronoi point. F2-F1 is
// small on cell borders: the caustic web and the foam net are both made of it.
vec2 cells(vec2 x, float t){
 vec2 n=floor(x),f=fract(x);float f1=8.0,f2=8.0;
 for(int j=-1;j<=1;j++)for(int i=-1;i<=1;i++){
  vec2 g=vec2(float(i),float(j));vec2 o=cell_hash(n+g);o=.5+.38*sin(t+6.2831*o);
  vec2 r=g+o-f;float d=dot(r,r);
  f2=d<f1 ? f1 : min(f2,d);f1=min(f1,d);
 }
 return sqrt(vec2(f1,f2));
}
void vertex(){mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(Nw*NORMAL);MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;}
void fragment(){
 float depth=max(UV.x,0.0);float d=UV2.x;float ocean=COLOR.r;
 float t=TIME*wave_speed;
 vec2 q=wp.xz;
 float pixel=length(fwidth(q));
 float sea=ocean*(1.0-river_surface);
 // Shallows: two flat tones from shore distance (exact out to .45) and depth,
 // the boundary warped by noise before the threshold, under a caustic web.
 float reach=d+depth*3.0;
 float warp=(tile(q*.06+vec2(t*.05,0.0))-.5)*.16+(tile(q*.25)-.5)*.08;
 vec3 shallow=vec3(.40,.83,.81);
 vec3 mid=mix(vec3(.24,.66,.74),vec3(.20,.64,.78),ocean);
 float to_mid=edge(reach+warp,mix(.10,.20,ocean));
 vec3 c=mix(shallow,mid,to_mid);
 c=mix(c,mix(shallow,mid,.55),river_surface);
 // Open sea, by depth alone (about .04 per unit offshore): three deeper flat
 // blues. Their boundaries wobble a unit or so with the noise.
 float deepness=depth+(tile(q*.045+vec2(.2,.7))-.5)*.08+(tile(q*.2)-.5)*.02;
 c=mix(c,vec3(.15,.55,.79),edge(deepness,.065)*sea);
 c=mix(c,vec3(.13,.50,.77),edge(deepness,.15)*sea);
 c=mix(c,vec3(.12,.45,.73),edge(deepness,.27)*sea);
 float waves=sea*smoothstep(.09,.16,deepness);
 // Wave fronts run across a fixed wind direction.
 vec2 front=vec2(.83,.56);vec2 normal=vec2(-.56,.83);
 float along=dot(q,front);float across=dot(q,normal);
 // Open-sea wave marks: sparse hand-designed white crescents and curls
 // (wave_marks.png, a signed distance field baked by tools/make_wave_marks.py)
 // laid along the wave fronts. Two layers at different scales hide the
 // tiling. Each set grows from its thick middle and shrinks back on its own
 // cycle, and a large noise leaves calm stretches with none.
 float marks=0.0;
 for(int k=0;k<2;k++){
  float scale=k==0 ? 8.0 : 11.0;
  vec2 o=k==0 ? vec2(0.0) : vec2(.37,.61);
  vec2 mq=vec2(along,across-TIME*.05)/scale+o+(vec2(tile(q*.08+o),tile(q*.08+o.yx))-.5)*.04;
  vec2 m=texture(wave_marks,mq).rg;
  float grow=smoothstep(.0,.45,sin(3.14159*fract(TIME*.045+m.g+float(k)*.5)));
  float calm=smoothstep(.36,.56,tile(q*.025+o*3.0));
  marks=max(marks,edge(m.r,mix(.64,.5,grow*calm*waves)));
 }
 marks*=1.0-smoothstep(.06,.12,pixel);
 // Caustic web in the shallows: Voronoi cell borders, warped so they wobble,
 // drifting slowly. The border threshold shrinks with depth, so offshore the
 // web thins and breaks into fragments before it disappears.
 vec2 cw=q/.34+vec2(tile(q*.18+t*.03),tile(q*.18+vec2(.5,.3)-t*.03))*1.4;
 vec2 v=cells(cw,TIME*.45);
 float web=.09*(1.0-smoothstep(.02,.10,deepness));
 float caustic=(1.0-edge(v.y-v.x,web))*step(.001,web)*(1.0-to_mid*.8)*(1.0-smoothstep(.04,.08,pixel));
 // Shore foam: a white sheet on the shallows next to the beach, holed by
 // rounded Voronoi cells that grow toward its outer edge, so it reads as
 // bubbles opening up rather than a line. The outer boundary breathes with two
 // staggered wave sets and is warped by noise before the threshold; an
 // incoming crest is a broken white line on the shore-distance field.
 float aa=max(fwidth(d),.002);
 float foam_zone=0.0;float crest_line=0.0;
 for(int k=0;k<2;k++){
  vec2 o=k==0 ? vec2(0.0) : vec2(17.3,5.1);
  float ta=t*1.6+.5*float(k)+tile(q*.08+o)*1.4;
  float travel=fract(ta);
  float at=mix(.42,.03,travel*travel*(3.0-2.0*travel));
  float alive=smoothstep(0.0,.15,travel)*(1.0-smoothstep(.80,1.0,travel));
  float piece=smoothstep(.40,.60,tile(q*.22+o+floor(ta)*vec2(.31,.17)));
  crest_line=max(crest_line,(1.0-edge(abs(d-at),.010+.016*travel))*alive*piece);
  float landed=fract(ta+.05);
  foam_zone=max(foam_zone,.08+.16*smoothstep(0.0,.10,landed)*(1.0-smoothstep(.15,.90,landed)));
 }
 float foam_edge=foam_zone+(tile(q*.5+vec2(t*.2,0.0))-.5)*.08;
 float sheet=1.0-edge(d,foam_edge);
 vec2 fc=cells(q/.06+vec2(tile(q*.5),tile(q*.5+vec2(.4,.7)))*1.0,TIME*.6);
 float opening=smoothstep(.0,1.0,d/max(foam_edge,.01));
 float holes=1.0-edge(fc.x,mix(.05,.42,opening));
 float surf=sea*shore_bands*(1.0-smoothstep(.03,.07,aa));
 float foam=max(sheet*(1.0-holes),crest_line*(1.0-smoothstep(.05,.10,pixel)))*surf;
 vec3 white=vec3(.95,.99,1.0);
 c=mix(c,mix(c,white,.65),caustic*(1.0-foam));
 c=mix(c,white,marks);
 c=mix(c,white,foam);
 float cliff=smoothstep(.26,.65,UV2.y);float broken=smoothstep(.40,.77,.5+.5*sin(wp.x*4.7-wp.z*3.3));
 c=mix(c,vec3(.84,.95,.89),(1.0-smoothstep(.018,.06,d))*cliff*sea*broken*shore_bands*.58);
 palette_lit=c;palette_shade=shade_endpoint(c);
 form_mask=1.0-smoothstep(.20,.30,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
 ALBEDO=vec3(1.0);ROUGHNESS=1.0;
}

// Water-only projection AA candidate. Original ripple/geometry/palette unchanged.
// Filtered real visibility retains two exact endpoints; threshold footprint is
// approximately one raster pixel instead of the shared .020 scalar cap.
uniform bool water_projection_antialiasing=false;
vec3 shade_water_projection_once(vec3 lit,vec3 shade,float form,float cast){
 float mask=clamp(max(form,cast),0.0,1.0);
 if(shadow_debug==1)return vec3(form,cast,mask);
 if(shadow_debug==2)return vec3(1.0-cast);
 if(shadow_debug==3)return vec3(form);
 float derivative=max(fwidth(mask),1.0/255.0);
 float aa=clamp(.5*derivative,1.0/255.0,.5);
 float two_band=smoothstep(.5-aa,.5+aa,mask);
 vec3 base=mix(lit,shade,two_band);
 // Preserve the original once-unioned coloured narrow contour expression.
 float edge_distance=(mask-.5)/derivative;
 float band=smoothstep(.0,.15,edge_distance)*(1.0-smoothstep(.85,1.25,edge_distance));
 vec3 edge=saturated(shade,1.45);
 return clamp(mix(base,edge,band),vec3(0.0),vec3(1.0));
}
void light(){
 vec3 c=water_projection_antialiasing ? shade_water_projection_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION) : shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
 DIFFUSE_LIGHT+=decode(c);
}

