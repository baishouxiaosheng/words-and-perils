shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "palette.gdshaderinc"
varying vec3 wn;
varying float local_height;
void vertex() {
    // MODEL_MATRIX includes each MultiMesh instance's nonuniform scale.
    // Write the receiver normal matrix; never double-transform NORMAL or VERTEX.
    mat3 Nw=transpose(inverse(mat3(MODEL_MATRIX)));
    wn=normalize(Nw*NORMAL);
    MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;
    local_height=VERTEX.y;
}
void fragment() {
    vec3 source=encode(COLOR.rgb);
    float leaf=step(source.r*.99,source.g);
    float tropical=smoothstep(.65,.86,source.b/max(source.r,.001));
    vec3 crown=mix(vec3(.514,.678,.310),vec3(.25,.63,.46),tropical);
    float variation=clamp(source.g/.52,.82,1.12);
    palette_lit=mix(vec3(.56,.36,.24)*variation,crown*variation,leaf);
    palette_lit*=mix(.86,1.0,smoothstep(.18,.90,local_height));
    palette_shade=shade_endpoint(palette_lit);
    form_mask=1.0-smoothstep(.23,.34,dot(normalize(wn),normalize(vec3(-.55,.74,.39))));
    ALBEDO=vec3(1.0);
    ROUGHNESS=1.0;
}
void light() {
    vec3 c=shade_once(palette_lit,palette_shade,form_mask,1.0-ATTENUATION);
    // Godot encodes custom-light accumulation on output; supply linear radiance.
    DIFFUSE_LIGHT+=decode(c);
}
