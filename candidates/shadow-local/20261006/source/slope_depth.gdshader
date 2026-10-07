shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// A shadow-only proxy material. No visible receiver uses this shader.
// The enabled flag is the sole production candidate variable.
uniform bool slope_bias_enabled = false;
// Test-only route proof: far depth must match hiding just the mountain proxy.
uniform bool depth_route_probe = false;

void vertex() {
    // Godot 4.6.3 GLES3 replaces fragment-only shaders with a shared default
    // shadow material. This explicit identity WRITE sets uses_vertex=true so
    // the directional shadow pass executes our material. Geometry is unchanged.
    VERTEX = VERTEX;
}

void fragment() {
    float depth = FRAGCOORD.z;
    if (IN_SHADOW_PASS) {
        if (depth_route_probe) {
            depth = 0.0;
        } else if (slope_bias_enabled) {
            // Half a texel's corner-to-center planar depth variation, plus one
            // 24-bit depth quantum. Derivatives are in the active cascade's
            // raster space, so no camera/world distance estimate is needed.
            // Reverse-Z: lower stored depth moves the caster away from light.
            float half_texel = 0.5 * (abs(dFdx(FRAGCOORD.z)) + abs(dFdy(FRAGCOORD.z)));
            depth -= half_texel + 1.0 / 16777215.0;
        }
    }
    // Write every branch. The diagnostic must show this runs in shadow depth,
    // rather than changing a color pass or discarding visible triangles.
    DEPTH = clamp(depth, 0.0, 1.0);
    ALBEDO = vec3(1.0);
}
