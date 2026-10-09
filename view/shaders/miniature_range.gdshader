shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

// Retains depth testing: foreground hills/miniatures occlude range ribbons.
// Geometry is draped by the board above the real terrain, not a floating HUD.
uniform vec4 range_color : source_color = vec4(0.32, 0.79, 0.66, 0.14);
uniform float pulse_strength : hint_range(0.0, 0.15) = 0.055;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    float breath = 1.0 + sin(TIME * 1.3 + world_position.x * 0.12 + world_position.z * 0.1) * pulse_strength;
    ALBEDO = range_color.rgb;
    EMISSION = range_color.rgb * 0.20;
    ALPHA = range_color.a * breath;
}
