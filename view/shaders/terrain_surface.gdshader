shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Source albedos are sRGB; normal and roughness maps are unconverted data.
// Mipmapped anisotropic filtering avoids both distant shimmer and grazing blur.
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

uniform bool software_preview = false;
uniform float grass_patch_m : hint_range(0.25, 8.0) = 2.0;
uniform float rock_patch_m : hint_range(0.25, 8.0) = 2.4;
// 1 = actual source dimensions, 2 = twice the texel density, no per-hex UV reset.
uniform float texel_density : hint_range(0.5, 3.0) = 1.0;
uniform float grass_normal_strength : hint_range(0.0, 1.5) = 0.58;
uniform float rock_normal_strength : hint_range(0.0, 1.5) = 0.72;
uniform float biome_tint_strength : hint_range(0.0, 0.3) = 0.10;
uniform float rock_height_start : hint_range(0.0, 3.0) = 0.48;
uniform float rock_height_end : hint_range(0.1, 5.0) = 1.25;
uniform float rock_slope_start : hint_range(0.0, 0.9) = 0.15;
uniform float rock_slope_end : hint_range(0.1, 1.0) = 0.52;
uniform float projection_sharpness : hint_range(1.0, 8.0) = 4.0;
uniform float roughness_scale : hint_range(0.5, 1.2) = 1.0;
// Palette changes only chromaticity and a bounded material gain, never lighting.
uniform vec3 grass_palette : source_color = vec3(0.403922, 0.552941, 0.262745);
uniform vec3 rock_palette : source_color = vec3(0.537255, 0.564706, 0.513725);
uniform float grass_palette_strength : hint_range(0.0, 0.7) = 0.70;
uniform float rock_palette_strength : hint_range(0.0, 0.7) = 0.60;
uniform float grass_albedo_gain : hint_range(0.5, 2.0) = 0.75;
uniform float rock_albedo_gain : hint_range(0.5, 2.0) = 1.05;
uniform float dielectric_specular : hint_range(0.0, 1.0) = 0.5;

varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;

void vertex() {
    terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    terrain_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    // TerrainField COLOR is already linear. Pass it through exactly once.
    // Do not generate tangents or displace the approved low-poly surface.
}

// Decode XY and reconstruct Z, so BC5/RGTC normal imports also work.
vec2 normal_slopes(vec3 encoded, float strength) {
    vec2 xy = encoded.xy * 2.0 - 1.0;
    float z = sqrt(max(1.0 - dot(xy, xy), 0.05));
    return xy * strength / max(z, 0.38);
}

void fragment() {
    vec3 p = terrain_world_position;
    vec3 n = normalize(terrain_world_normal);
    if (!FRONT_FACING) { n = -n; }
    float slope = 1.0 - abs(n.y);
    float slope_rock = smoothstep(rock_slope_start, rock_slope_end, slope);
    float height_rock = smoothstep(rock_height_start, rock_height_end, p.y);
    // Height and slope keep low meadows grassy and expose high/steep rock.
    float rock_mix = 1.0 - (1.0 - slope_rock) * (1.0 - height_rock);
    vec3 weights = pow(abs(n), vec3(projection_sharpness));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    vec3 face_sign = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), n));
    vec2 grass_uv = p.xz * vec2(1.0, -1.0) * texel_density / grass_patch_m;
    vec3 rock_p = p * texel_density / rock_patch_m;
    // Vertical texture V follows world height: rock fissures/strata aren't
    // stretched down cliffs by a top-down XZ projection.
    vec2 uv_x = vec2(rock_p.z * face_sign.x, -rock_p.y);
    vec2 uv_y = vec2(rock_p.x * face_sign.y, -rock_p.z);
    vec2 uv_z = vec2(-rock_p.x * face_sign.z, -rock_p.y);

    vec3 grass_color = vec3(0.0);
    vec3 rock_color = vec3(0.0);
    float grass_r = 1.0;
    float rock_r = 1.0;
    vec3 grass_detail = vec3(0.0);
    vec3 rock_detail = vec3(0.0);

    if (rock_mix < 0.999) {
        grass_color = texture(grass_albedo, grass_uv).rgb;
        grass_r = texture(grass_roughness, grass_uv).r;
        vec2 detail = normal_slopes(texture(grass_normal, grass_uv).rgb,
            grass_normal_strength * (software_preview ? 0.65 : 1.0));
        grass_detail = vec3(detail.x, 0.0, -detail.y);
    }
    if (rock_mix > 0.001) {
        rock_color = texture(rock_albedo, uv_x).rgb * weights.x
            + texture(rock_albedo, uv_y).rgb * weights.y
            + texture(rock_albedo, uv_z).rgb * weights.z;
        rock_r = texture(rock_roughness, uv_x).r * weights.x
            + texture(rock_roughness, uv_y).r * weights.y
            + texture(rock_roughness, uv_z).r * weights.z;
        if (software_preview) {
            // Keep full triplanar albedo/roughness. Only micro-normal reads
            // reduce to one axis; lighting still uses each real mesh facet.
            vec2 detail;
            if (weights.y >= weights.x && weights.y >= weights.z) {
                detail = normal_slopes(texture(rock_normal, uv_y).rgb, rock_normal_strength * 0.55);
                rock_detail = vec3(detail.x * face_sign.y, 0.0, -detail.y);
            } else if (weights.x >= weights.z) {
                detail = normal_slopes(texture(rock_normal, uv_x).rgb, rock_normal_strength * 0.55);
                rock_detail = vec3(0.0, -detail.y, detail.x * face_sign.x);
            } else {
                detail = normal_slopes(texture(rock_normal, uv_z).rgb, rock_normal_strength * 0.55);
                rock_detail = vec3(-detail.x * face_sign.z, -detail.y, 0.0);
            }
        } else {
            vec2 detail_x = normal_slopes(texture(rock_normal, uv_x).rgb, rock_normal_strength);
            vec2 detail_y = normal_slopes(texture(rock_normal, uv_y).rgb, rock_normal_strength);
            vec2 detail_z = normal_slopes(texture(rock_normal, uv_z).rgb, rock_normal_strength);
            rock_detail = vec3(0.0, -detail_x.y, detail_x.x * face_sign.x) * weights.x
                + vec3(detail_y.x * face_sign.y, 0.0, -detail_y.y) * weights.y
                + vec3(-detail_z.x * face_sign.z, -detail_z.y, 0.0) * weights.z;
        }
    }

    // Preserve texture albedo. Only a small chromatic biome residual comes
    // from vertex colors; their old large-scale brightness clouds are omitted.
    vec3 biome = COLOR.rgb / max(dot(COLOR.rgb, vec3(0.333333)), 0.04);
    vec3 biome_tint = mix(vec3(1.0), clamp(biome, vec3(0.78), vec3(1.22)), biome_tint_strength);
    const vec3 luminance_weights = vec3(0.2126, 0.7152, 0.0722);
    float grass_luma = dot(grass_color, luminance_weights);
    float rock_luma = dot(rock_color, luminance_weights);
    grass_color = mix(grass_color, grass_palette * grass_luma
        / max(dot(grass_palette, luminance_weights), 0.001), grass_palette_strength) * grass_albedo_gain;
    rock_color = mix(rock_color, rock_palette * rock_luma
        / max(dot(rock_palette, luminance_weights), 0.001), rock_palette_strength) * rock_albedo_gain;
    ALBEDO = clamp(mix(grass_color * biome_tint, rock_color, rock_mix), vec3(0.0), vec3(0.95));
    METALLIC = 0.0;
    SPECULAR = dielectric_specular;
    // Do not bake highlights, erase maps, or force all terrain matte.
    ROUGHNESS = clamp(mix(grass_r, rock_r, rock_mix) * roughness_scale, 0.16, 0.98);
    vec3 detail = mix(grass_detail, rock_detail, rock_mix);
    // Surface-gradient projection preserves each original triangular plane.
    // A neutral map is exactly the geometric normal, even on blended axes.
    detail -= n * dot(n, detail);
    vec3 shading_normal = normalize(n + detail);
    NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
}
