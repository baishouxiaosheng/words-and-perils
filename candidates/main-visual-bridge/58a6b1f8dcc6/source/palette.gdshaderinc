// One palette evaluation for form and cast shadow. Endpoints are exact.
uniform int shadow_debug=0;
vec3 decode(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 encode(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
vec3 saturated(vec3 c,float strength){
    float luma=dot(c,vec3(.2126,.7152,.0722));
    return clamp(mix(vec3(luma),c,strength),vec3(0.0),vec3(1.0));
}
// Preserve the painted hue instead of pulling every material toward blue-grey.
vec3 shade_endpoint(vec3 base) { return saturated(base,1.20)*.60; }
vec3 shade_once(vec3 lit, vec3 shade, float form, float cast) {
    float mask=clamp(max(form,cast),0.0,1.0);
    if(shadow_debug==1)return vec3(form,cast,mask);
    if(shadow_debug==2)return vec3(1.0-cast); // Raw ATTENUATION, before union
    if(shadow_debug==3)return vec3(form); // Authored surface form only
    // Real filtered visibility selects two clear paint endpoints. Do not use
    // the broad PCF ramp as a broad colour blend. AA is capped to a narrow ramp.
    float derivative=max(fwidth(mask),.0039215686);
    float aa=clamp(derivative*.50,.0039215686,.020);
    float two_band=smoothstep(.5-aa,.5+aa,mask);
    vec3 base=mix(lit,shade,two_band);
    // A one-pixel inner contour, computed ONCE from the union. A cast boundary
    // inside an already-full form shadow has mask=1 and cannot shade it twice.
    float edge_distance=(mask-.5)/derivative;
    float band=smoothstep(.0,.15,edge_distance)*(1.0-smoothstep(.85,1.25,edge_distance));
    vec3 edge=saturated(shade,1.45);
    return clamp(mix(base,edge,band),vec3(0.0),vec3(1.0));
}
varying vec3 palette_lit;
varying vec3 palette_shade;
varying float form_mask;
