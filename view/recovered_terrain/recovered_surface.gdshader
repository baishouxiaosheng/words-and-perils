shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap, repeat_enable;
uniform float texture_patch = 2.4;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 vec3 n = normalize(world_normal);
 float rock = smoothstep(0.035,0.18,1.0-abs(n.y));
 vec2 uv = world_position.xz / texture_patch;
 vec3 grass = texture(grass_albedo,uv).rgb;
 // Single dominant-plane projection, no repeated triplanar normal samples.
 vec3 an = abs(n);
 vec2 ruv = uv;
 if (an.x>an.y && an.x>an.z) ruv=world_position.zy/texture_patch;
 else if (an.z>an.y) ruv=world_position.xy/texture_patch;
 vec3 stone = texture(rock_albedo,ruv).rgb;
 float gl = dot(grass,vec3(0.2126,0.7152,0.0722));
 float rl = dot(stone,vec3(0.2126,0.7152,0.0722));
 vec3 grass_detail=mix(vec3(gl),grass,0.24);
 vec3 stone_detail=mix(vec3(rl),stone,0.30);
 ALBEDO = clamp(mix(COLOR.rgb*grass_detail*2.5,vec3(0.56,0.51,0.41)*stone_detail*2.5,rock),vec3(0.0),vec3(0.85));
 ROUGHNESS=clamp(mix(texture(grass_roughness,uv).r,texture(rock_roughness,ruv).r,rock),0.68,0.98);
 SPECULAR=0.18;
 METALLIC=0.0;
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
