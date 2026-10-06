// One palette evaluation for form and cast shadow. Endpoints are exact.
uniform int shadow_debug=0;
vec3 decode(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 encode(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
vec3 shade_endpoint(vec3 base) { return base*vec3(.62,.74,.86); }
vec3 shade_once(vec3 lit, vec3 shade, float form, float cast) {
    float mask=clamp(max(form,cast),0.0,1.0);
    if(shadow_debug==1)return vec3(form,cast,mask);
    vec3 base=mix(lit,shade,mask);
    // Saturate the CURRENT transition color, never inject a blue shadow outline.
    float band=smoothstep(.12,.34,mask)*(1.0-smoothstep(.60,.82,mask));
    float luma=dot(base,vec3(.2126,.7152,.0722));
    vec3 edged=mix(vec3(luma),base,1.0+.12*band);
    return clamp(edged,min(lit,shade),max(lit,shade));
}
varying vec3 palette_lit;
varying vec3 palette_shade;
varying float form_mask;
