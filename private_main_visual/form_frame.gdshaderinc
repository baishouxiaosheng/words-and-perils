// Per-model light frame written by form_frame.gd. Unset nodes keep radius 0,
// which turns the model-relative grades off.
instance uniform vec4 form_frame=vec4(0.0);
instance uniform vec3 form_span=vec3(0.0,1.0,-1.0);
varying float form_u;
varying float form_size;
// x: position along the sun in model radii; y: model radius in world units.
vec2 form_coordinate(mat4 model, vec3 vertex) {
    float s=(length(model[0].xyz)+length(model[1].xyz)+length(model[2].xyz))/3.0;
    float size=form_frame.w*s;
    float u=dot((model*vec4(vertex-form_frame.xyz,0.0)).xyz,normalize(vec3(-.55,.74,.39)))/max(size,.0001);
    return vec2(u,size);
}
// x: lit grade from the model's terminator (0) to its sun end (1), blended with
// the face key so facets still separate. y: signed shade grade, core shadow at
// the terminator (-1) to the far side (+1). Small parts fade to the face key only.
vec2 form_grades(float key_t) {
    float k=smoothstep(.08,.6,form_size);
    float lit_t=clamp((form_u-form_span.x)/max(form_span.y-form_span.x,.05),0.0,1.0);
    float shade_t=clamp((form_span.x-form_u)/max(form_span.x-form_span.z,.05),0.0,1.0);
    return vec2(mix(key_t,mix(key_t,lit_t,.65),k),(shade_t*2.0-1.0)*k);
}
