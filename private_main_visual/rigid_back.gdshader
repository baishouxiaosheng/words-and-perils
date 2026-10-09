shader_type spatial;
render_mode cull_back, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
uniform vec4 base_color : source_color = vec4(1.0);
// 0: registered token/prop base color; 1: authored settlement display colors;
// 2: registered city glTF linear COLOR_0 with the exact existing trim lift.
uniform int vertex_rule=0;
uniform float form_low=.20;
uniform float form_high=.30;
uniform float metallic=0.0;
uniform float gloss=0.0;
varying vec3 wn;
void vertex(){
    mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));
    wn=normalize(Nw*NORMAL);
    MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;
}
void fragment(){
    vec3 c=OUTPUT_IS_SRGB ? base_color.rgb : encode(base_color.rgb);
    if(vertex_rule==1)c*=COLOR.rgb;
    if(vertex_rule==2){
        vec3 linear=COLOR.rgb;
        float value=max(linear.r,max(linear.g,linear.b));
        float dark_trim=1.0-smoothstep(.132868,.233022,value);
        c*=encode(linear*(1.0+.16*dark_trim));
    }
    vec3 n=normalize(wn);
    c*=mix(1.0,.80,metallic);
    palette_lit=face_lit(c,n);palette_shade=face_shade(c,n);
    form_mask=1.0-smoothstep(form_low,form_high,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
    ALBEDO=vec3(1.0);ROUGHNESS=1.0;
}
void light(){
    float mask=max(form_mask,1.0-ATTENUATION);
    vec3 c=shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
    DIFFUSE_LIGHT+=decode(glint(c,palette_lit,mask,NORMAL,LIGHT,VIEW,metallic,gloss));
}
