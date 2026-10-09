## tokens.gd — palette, spacing, and asset-slot definitions.
## Units: authored logical source pixels; displayed padding uses a separate scale. Scale with layout.scale_for().
## Colour order: normal, hover, pressed, disabled (where arrays of 4).
extends RefCounted

# ── Palette ──────────────────────────────────────────────────────────────────
const PARCHMENT        := Color(0.949, 0.910, 0.816)   # panel fill light
const PARCHMENT_MID    := Color(0.898, 0.847, 0.737)   # panel fill shadow
const LEATHER          := Color(0.545, 0.369, 0.235)   # frame border
const LEATHER_DARK     := Color(0.420, 0.259, 0.149)   # pressed / deep seam
const BRASS            := Color(0.788, 0.659, 0.294)   # fasteners, ornament
const BRASS_LIGHT      := Color(0.875, 0.761, 0.420)   # hover highlight
const TEAL             := Color(0.180, 0.490, 0.431)   # turn-button face
const TEAL_LIGHT       := Color(0.231, 0.580, 0.510)   # turn-button hover
const TEAL_PRESSED     := Color(0.137, 0.380, 0.329)   # turn-button pressed
const INK              := Color(0.239, 0.169, 0.122)   # primary text
const INK_FADED        := Color(0.459, 0.369, 0.282)   # hint / placeholder
const INK_DISABLED     := Color(0.30, 0.23, 0.17)   # disabled text
const HISTORY_BG       := Color(0.949, 0.910, 0.816, 0.72)  # translucent parchment
const FOCUS_RING       := Color(0.788, 0.659, 0.294, 0.85)  # brass keyboard ring

# ── Spacing (logical px) ─────────────────────────────────────────────────────
const BASE_PADDING     := 8    # smallest pad unit
const BORDER_RADIUS    := 4    # fallback flat corner radius
const BORDER_WIDTH     := 2    # fallback flat border width

# ── State names ──────────────────────────────────────────────────────────────
const STATE_NORMAL         := "normal"
const STATE_HOVER          := "hover"
const STATE_PRESSED        := "pressed"
const STATE_HOVER_PRESSED  := "hover_pressed"
const STATE_DISABLED       := "disabled"

# ── Asset slot defaults ───────────────────────────────────────────────────────
# Each entry: { size, slice[L,T,R,B], padding[L,T,R,B], uniform, text_inset, aperture, radius }
# size: source texture logical dimensions (Vector2i)
# slice: 9-slice margins in px — corners stay outside stretch bands
# padding: inner content inset from border
# uniform: true for a uniformly scaled whole image (zero nine-slice margins)
# text_inset: extra inset for text inside turn_button
# aperture/radius: for minimap circular cutout centre and radius
func slot_defaults() -> Dictionary:
	return {
		"intent_base": {
			"size":       Vector2i(256, 144),
			"slice":      [38, 30, 38, 30],   # L T R B
			"padding":    [26, 18, 26, 18],
			"uniform":    false,
		},
		"dialogue_base": {
			"size":       Vector2i(256, 100),
			"slice":      [36, 24, 36, 24],
			"padding":    [30, 18, 30, 18],
			"uniform":    false,
		},
		"history_base": {
			"size":       Vector2i(256, 180),
			"slice":      [42, 40, 42, 40],
			"padding":    [32, 28, 32, 26],
			"uniform":    false,
		},
		"portrait_frame": {
			"size":       Vector2i(140, 160),
			"slice":      [0, 0, 0, 0],
			"padding":    [14, 16, 14, 16],
			"uniform":    true,
		},
		"turn_button": {
			"size":       Vector2i(144, 144),
			"slice":      [0, 0, 0, 0],
			"padding":    [34, 34, 34, 34],
			"uniform":    true,
			"text_inset": 34,
		},
		"minimap_frame": {
			"size":       Vector2i(284, 300),
			"slice":      [0, 0, 0, 0],
			"padding":    [8,  8,  8,  8],
			"uniform":    true,
			"aperture":   Vector2i(142, 132),
			"radius":     94,
		},
		"quill": {
			"size":       Vector2i(76, 162),
			"slice":      [0, 0, 0, 0],
			"padding":    [4,  8,  4,  8],
			"uniform":    true,
		},
		"tool_button": {
			"size":       Vector2i(64, 64),
			"slice":      [0, 0, 0, 0],
			"padding":    [10, 10, 10, 10],
			"uniform":    true,
		},
	}

# ── Merge caller overrides into a fresh copy of the defaults ─────────────────
func merged_slot(slot_name: String, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = slot_defaults()
	if not base.has(slot_name):
		return overrides.duplicate()
	var result: Dictionary = base[slot_name].duplicate(true)
	for k in overrides:
		result[k] = overrides[k]
	return result
