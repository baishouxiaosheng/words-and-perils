shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
uniform sampler2D visual_weights : filter_linear, repeat_disable;
uniform vec2 world_min=vec2(-44.1673,-38.5);
uniform vec2 world_extent=vec2(88.3346,77.0);
varying vec3 wn;
varying vec2 world_xz;
void vertex() {
    mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));
    wn=normalize(Nw*NORMAL);
    MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;
    world_xz=(MODEL_MATRIX*vec4(VERTEX,1)).xz;
}
void fragment() {
    float key=dot(normalize(wn),normalize(vec3(-.55,.74,.39)));
    float rock_form=1.0-smoothstep(.34,.44,key);
    vec3 rock=vec3(.80,.72,.60)*mix(.90,1.04,COLOR.r)*(.86+.14*clamp((key+.2)/1.2,0.0,1.0));
    vec4 w=max(texture(visual_weights,(world_xz-world_min)/world_extent),vec4(0));
    w/=max(dot(w,vec4(1)),.000001);
    vec3 foot=(w.r+w.g)*vec3(.659,.788,.373)+w.b*vec3(.606,.788,.384)+w.a*vec3(.80,.68,.39);
    // Grass climbs the authored foot band and meets rock on a crisp, pixel-AA line.
    float g=COLOR.g*4.0;float gw=max(fwidth(g),.002);
    float j=1.0-smoothstep(.05-gw,.05+gw,g);
    vec3 n=normalize(wn);
    // The grass foot belongs to the ground plane, so it takes the ground top tone.
    palette_lit=mix(face_lit(rock,n),face_lit(foot,vec3(0.0,1.0,0.0)),j);
    // Warm stone in light, violet-blue in shade: two clear paints, not grey on grey.
    vec3 rock_shade=vec3(.56,.55,.68)*mix(.92,1.04,COLOR.r)*mix(.90,1.05,smoothstep(-.2,.8,n.y));
    palette_shade=mix(rock_shade,face_shade(foot,vec3(0.0,1.0,0.0)),j);
    form_mask=mix(rock_form,0.0,j);
    ALBEDO=vec3(1.0);
    ROUGHNESS=1.0;
}
void light() {
    vec3 c=shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
    // Godot encodes custom-light accumulation on output; supply linear radiance.
    DIFFUSE_LIGHT+=decode(c);
}
