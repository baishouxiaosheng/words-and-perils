extends RefCounted
## Explicit source-authoring policy. Never apply to already saved/generated sources.
## Remove only an interior, isolated, near-sea-level land component whose raw
## cell-center linear surface has less than 5% of one complete hex of dry area.
## The six-triangle fan is a measurement stencil, not replacement render geometry.
const VERSION = "tiny_remnant_cleanup/v1"
const QUANTUM = 1.0 / 4096.0
const MAX_PEAK = 4.0 * QUANTUM
const MAX_FULL_HEX_FRACTION = 0.05
const AREA_METADATA_SCALE = 4294967296
const DIRECTIONS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]

static func inspect_cell(domain: Dictionary, cell_key: String) -> Dictionary:
	var c: Dictionary = domain[cell_key]
	var height = float(c.elevation)
	if bool(c.ocean) or height <= 0.0 or height > MAX_PEAK:
		return {}
	var surrounding: Array = []
	for direction in DIRECTIONS:
		var n = "%d,%d" % [int(c.q)+direction.x,int(c.r)+direction.y]
		# A cape/connected island or crop edge is never removed by this policy.
		if not domain.has(n) or not bool(domain[n].ocean) or float(domain[n].elevation)>0.0:
			return {}
		surrounding.append(float(domain[n].elevation))
	var fraction = 0.0
	for i in range(6):
		# Each center-neighbor-neighbor triangle is half a full regular hex.
		# Linear sea-level intersections give exact dry fraction t_a * t_b.
		var a = height/(height-surrounding[i])
		var b = height/(height-surrounding[(i+1)%6])
		fraction += 0.5*a*b
	if fraction >= MAX_FULL_HEX_FRACTION:
		return {}
	# Decision uses unrounded area. Persist integer fixed-point metadata: a fine
	# fractional float still has last-bit native JSON parsing drift on some cases.
	return {"cell":cell_key,"raw_peak":height,"raw_full_hex_fraction_q32":int(round(fraction*AREA_METADATA_SCALE)),"new_elevation":-QUANTUM}

static func apply_to_sampled_cells(domain: Dictionary, ordered_keys: Array) -> Dictionary:
	# Read the whole stencil snapshot before any write: no traversal-order effect.
	var changes: Array = []
	for cell_key in ordered_keys:
		var row = inspect_cell(domain,cell_key)
		if not row.is_empty(): changes.append(row)
	changes.sort_custom(func(a,b): return String(a.cell)<String(b.cell))
	for row in changes:
		domain[row.cell].elevation = row.new_elevation
		domain[row.cell].ocean = true
	return {"version":VERSION,"max_peak":MAX_PEAK,"max_full_hex_fraction":MAX_FULL_HEX_FRACTION,"area_metadata_scale":AREA_METADATA_SCALE,"replacement_elevation":-QUANTUM,"changed_cells":changes}
