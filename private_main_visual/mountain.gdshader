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
    vec3 rock=vec3(.68,.72,.79)*COLOR.r*(.86+.14*clamp((key+.2)/1.2,0.0,1.0));
    vec4 w=max(texture(visual_weights,(world_xz-world_min)/world_extent),vec4(0));
    w/=max(dot(w,vec4(1)),.000001);
    vec3 foot=(w.r+w.g)*vec3(.659,.788,.373)+w.b*vec3(.606,.788,.384)+w.a*vec3(.80,.68,.39);
    float j=1.0-smoothstep(.025,.14,COLOR.g*4.0);
    palette_lit=mix(rock,foot,j);
    palette_shade=mix(shade_endpoint(rock),shade_endpoint(foot),j);
    form_mask=mix(rock_form,0.0,j);
    ALBEDO=vec3(1.0);
    ROUGHNESS=1.0;
}
void light() {
    vec3 c=shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
    // Godot encodes custom-light accumulation on output; supply linear radiance.
    DIFFUSE_LIGHT+=decode(c);
}
