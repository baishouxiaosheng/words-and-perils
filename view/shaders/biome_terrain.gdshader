shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool software_preview=false;
uniform float grass_patch_m=2.0;
uniform float soil_patch_m=1.6;
uniform float rock_patch_m=2.4;
uniform float grass_albedo_gain=2.10;
uniform float soil_albedo_gain=0.70;
varying vec3 world_position;
varying vec3 world_normal;
varying vec2 biome_weights;

void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
    biome_weights=UV2;
}
vec2 slopes(vec3 encoded,float strength) {
    vec2 xy=encoded.xy*2.0-1.0;
    float z=sqrt(max(1.0-dot(xy,xy),0.05));
    return xy*strength/max(z,0.38);
}
void fragment() {
    vec3 p=world_position;
    vec3 n=normalize(world_normal);
    if (!FRONT_FACING) n=-n;
    float slope=1.0-abs(n.y);
    // Flat cap follows its biome. Rock is exposed by actual steep geometry or
    // a canonical alpine/exposed-rock weight, never by absolute elevation.
    float rock_mix=max(smoothstep(0.17,0.55,slope),clamp(biome_weights.y,0.0,1.0));
    float soil_mix=clamp(biome_weights.x,0.0,1.0);
    vec3 land_color=vec3(0.0);
    float land_r=1.0;
    vec3 land_detail=vec3(0.0);
    if (rock_mix<0.999) {
        vec3 grass_color=vec3(0.0); vec3 soil_color=vec3(0.0);
        float grass_r=1.0; float soil_r=1.0;
        vec2 grass_d=vec2(0.0); vec2 soil_d=vec2(0.0);
        if (soil_mix<0.999) {
            vec2 uv=p.xz*vec2(1.0,-1.0)/grass_patch_m;
            grass_color=texture(grass_albedo,uv).rgb;
            grass_r=texture(grass_roughness,uv).r;
            grass_d=slopes(texture(grass_normal,uv).rgb,software_preview ? 0.38 : 0.58);
        }
        if (soil_mix>0.001) {
            vec2 uv=p.xz*vec2(1.0,-1.0)/soil_patch_m;
            soil_color=texture(soil_albedo,uv).rgb;
            soil_r=texture(soil_roughness,uv).r;
            soil_d=slopes(texture(soil_normal,uv).rgb,software_preview ? 0.32 : 0.48);
        }
        vec3 source=mix(grass_color,soil_color,soil_mix);
        float luma=dot(source,vec3(0.2126,0.7152,0.0722));
        // Preserve source luminance/micro-chroma, while COLOR carries a broad
        // coherent biome palette and its genuine jungle/meadow value difference.
        vec3 detail=mix(vec3(luma),source,0.15);
        land_color=detail*COLOR.rgb*mix(grass_albedo_gain,soil_albedo_gain,soil_mix);
        land_r=mix(grass_r,soil_r,soil_mix);
        vec2 d=mix(grass_d,soil_d,soil_mix);
        land_detail=vec3(d.x,0.0,-d.y);
    }
    vec3 rock_color=vec3(0.0); float rock_r=1.0; vec3 rock_detail=vec3(0.0);
    if (rock_mix>0.001) {
        vec3 weights=pow(abs(n),vec3(4.0));
        weights/=max(weights.x+weights.y+weights.z,0.0001);
        vec3 face_sign=mix(vec3(-1.0),vec3(1.0),step(vec3(0.0),n));
        vec3 rp=p/rock_patch_m;
        vec2 ux=vec2(rp.z*face_sign.x,-rp.y);
        vec2 uy=vec2(rp.x*face_sign.y,-rp.z);
        vec2 uz=vec2(-rp.x*face_sign.z,-rp.y);
        rock_color=texture(rock_albedo,ux).rgb*weights.x+texture(rock_albedo,uy).rgb*weights.y+texture(rock_albedo,uz).rgb*weights.z;
        rock_r=texture(rock_roughness,ux).r*weights.x+texture(rock_roughness,uy).r*weights.y+texture(rock_roughness,uz).r*weights.z;
        if (software_preview) {
            vec2 d;
            if (weights.y>=weights.x && weights.y>=weights.z) {
                d=slopes(texture(rock_normal,uy).rgb,0.40); rock_detail=vec3(d.x*face_sign.y,0.0,-d.y);
            } else if (weights.x>=weights.z) {
                d=slopes(texture(rock_normal,ux).rgb,0.40); rock_detail=vec3(0.0,-d.y,d.x*face_sign.x);
            } else {
                d=slopes(texture(rock_normal,uz).rgb,0.40); rock_detail=vec3(-d.x*face_sign.z,-d.y,0.0);
            }
        } else {
            vec2 dx=slopes(texture(rock_normal,ux).rgb,0.72);
            vec2 dy=slopes(texture(rock_normal,uy).rgb,0.72);
            vec2 dz=slopes(texture(rock_normal,uz).rgb,0.72);
            rock_detail=vec3(0.0,-dx.y,dx.x*face_sign.x)*weights.x+vec3(dy.x*face_sign.y,0.0,-dy.y)*weights.y+vec3(-dz.x*face_sign.z,-dz.y,0.0)*weights.z;
        }
        float luma=dot(rock_color,vec3(0.2126,0.7152,0.0722));
        vec3 palette=vec3(0.248,0.276,0.230);
        rock_color=mix(rock_color,palette*luma/max(dot(palette,vec3(0.2126,0.7152,0.0722)),0.001),0.60)*1.05;
    }
    ALBEDO=clamp(mix(land_color,rock_color,rock_mix),vec3(0.0),vec3(0.95));
    ROUGHNESS=clamp(mix(land_r,rock_r,rock_mix),0.16,0.98);
    METALLIC=0.0; SPECULAR=0.5;
    vec3 detail=mix(land_detail,rock_detail,rock_mix);
    detail-=n*dot(n,detail);
    NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+detail),0.0)).xyz);
}
