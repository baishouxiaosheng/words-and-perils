// One palette evaluation for form and cast shadow. Endpoints are exact.
uniform int shadow_debug=0;
vec3 decode(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
vec3 encode(vec3 c) { return mix(c*12.92,1.055*pow(max(c,vec3(0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),c)); }
vec3 saturated(vec3 c,float strength){
    float luma=dot(c,vec3(.2126,.7152,.0722));
    return clamp(mix(vec3(luma),c,strength),vec3(0.0),vec3(1.0));
}
// Preserve the painted hue instead of pulling every material toward blue-grey.
// Shade keeps the painted hue, nudged slightly cool, never towards grey.
vec3 shade_endpoint(vec3 base) { return saturated(base,1.30)*vec3(.62,.66,.76); }
// Three-face coloured light: sun-facing tops warm, lit sides cooler and a step
// darker, shade cool. Up-facing shade keeps some sky bounce; side shade is deeper.
// Inside the lit band, faces near the terminator stay deeper and richer while
// faces turned to the sun go paler and less saturated, so the lit side is a
// gradient instead of one flat saturated colour.
vec3 face_lit(vec3 base, vec3 n) {
    float top=smoothstep(.55,.85,n.y);
    vec3 c=base*mix(vec3(.90,.92,.97),vec3(1.02,1.01,.97),top);
    float sunward=smoothstep(.40,.95,dot(n,normalize(vec3(-.55,.74,.39))));
    c=mix(saturated(c,1.04)*.95,saturated(c,.76)*1.03+vec3(.035,.030,.018),sunward);
    return clamp(c,vec3(0.0),vec3(1.0));
}
// Aerial gradient for the lit side only: the upper (farther) part of the screen
// is a little paler and cooler. Shade and the edge band are untouched.
vec3 lit_air(vec3 lit, vec2 screen_uv) {
    float far=1.0-smoothstep(.05,.95,screen_uv.y);
    float luma=dot(lit,vec3(.2126,.7152,.0722));
    vec3 air=mix(lit,vec3(luma)*vec3(.98,1.0,1.04)+.05,.35);
    return clamp(mix(lit,air,far*.5),vec3(0.0),vec3(1.0));
}
vec3 face_shade(vec3 base, vec3 n) {
    float up=smoothstep(-.2,.8,n.y);
    return shade_endpoint(base)*mix(vec3(.86,.86,.94),vec3(1.04,1.04,1.08),up);
}
// Banded highlight in the lit region only. Metal gets a broad tinted glint and
// matte surfaces get none, so the two read differently without PBR haze.
vec3 glint(vec3 c, vec3 lit, float mask, vec3 N, vec3 L, vec3 V, float metal, float gloss) {
    if(metal+gloss<=.05)return c;
    float nh=max(dot(N,normalize(L+V)),0.0);
    float th=mix(mix(.996,.975,gloss),.90,metal);
    float aa=max(fwidth(nh),.002);
    float s=smoothstep(th-aa,th+aa,nh)*(1.0-smoothstep(.45,.55,mask));
    vec3 hi=mix(vec3(1.0),clamp(saturated(lit,1.3)+.38,vec3(0.0),vec3(1.0)),metal);
    return mix(c,hi,s*mix(.30*gloss,.90,metal));
}
vec3 shade_once(vec3 lit, vec3 shade, float form, float cast) {
    float mask=clamp(max(form,cast),0.0,1.0);
    if(shadow_debug==1)return vec3(form,cast,mask);
    if(shadow_debug==2)return vec3(1.0-cast); // Raw ATTENUATION, before union
    if(shadow_debug==3)return vec3(form); // Authored surface form only
    // Real filtered visibility selects two clear paint endpoints. Do not use
    // the broad PCF ramp as a broad colour blend. AA is capped to a narrow ramp.
    float derivative=max(fwidth(mask),.0039215686);
    float aa=clamp(derivative*.75,.0039215686,.040);
    float two_band=smoothstep(.5-aa,.5+aa,mask);
    vec3 base=mix(lit,shade,two_band);
    // A one-pixel inner contour, computed ONCE from the union. A cast boundary
    // inside an already-full form shadow has mask=1 and cannot shade it twice.
    float edge_distance=(mask-.5)/derivative;
    // About two pixels wide so the saturated rim stays visible at 1080p.
    float band=smoothstep(.0,.2,edge_distance)*(1.0-smoothstep(1.6,2.3,edge_distance));
    vec3 edge=saturated(shade,1.85)*.94;
    return clamp(mix(base,edge,band),vec3(0.0),vec3(1.0));
}
varying vec3 palette_lit;
varying vec3 palette_shade;
varying float form_mask;
