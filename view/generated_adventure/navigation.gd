extends RefCounted
## Exact dry half-edges on the existing macro renderer's piecewise-linear triangles.
## This is a separately versioned source adapter, never the authored-room shortcut.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Field = preload("res://view/terrain_field.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const ID := "macro_render_dry_edges/v1"
const CLEARANCE := 0.0001
var source_hash := ""
var allowed: Dictionary = {}
var supported: Dictionary = {}
var support_heights: Dictionary = {}
var diagnostics: Dictionary = {}

func build(source: Dictionary) -> Dictionary:
	allowed.clear(); supported.clear(); support_heights.clear()
	var tiles := {}
	for key in source.hexes:
		var row: Dictionary = source.hexes[key]
		tiles[key] = {"hex":Vector2i(row.q,row.r),"terrain":row.terrain,"raw":row}
	var field := Field.new()
	if not field.configure(tiles,source): return C.fail("GENERATED_NAV_SOURCE","The exact generated renderer field could not be configured.")
	var halves := {}; var vertices := {}; var triangles := 0
	for key in tiles:
		var tile: Dictionary = tiles[key]
		var center: Vector3 = Field.center(tile.hex)
		var signed_center: float = field.land_height(center)-field.water_height(center)
		supported[key] = signed_center > CLEARANCE and not source.hexes[key].ocean
		support_heights[key] = field.land_height(center)
		allowed[key] = []
		halves[key] = {}
		if not supported[key]: continue
		var n := 12 if tile.raw.get("river",false) else 6
		var faces: Array = []
		for side in range(6):
			var a := Field.corner(side); var b := Field.corner(side+1)
			for u in range(n):
				for v in range(n-u):
					var p := center+(a*u+b*v)/n
					faces.append([p,p+b/n,p+a/n])
					if u+v<n-1: faces.append([p+a/n,p+b/n,p+(a+b)/n])
		triangles += faces.size()
		for direction in Traversal.DIRECTIONS:
			var target := [int(tile.hex.x)+direction[0],int(tile.hex.y)+direction[1]]
			var target_key := Traversal.key(target)
			if not tiles.has(target_key): continue
			var end: Vector3 = center.lerp(Field.center(tiles[target_key].hex),0.5)
			var dry := true; var covered := 0.0
			for face in faces:
				var interval := triangle_interval(Vector2(center.x,center.z),Vector2(end.x,end.z),face)
				if interval.is_empty() or interval[1]-interval[0] < 0.0000001: continue
				covered += float(interval[1])-float(interval[0])
				var clearances: Array = []
				for p in face:
					var vertex_key := "%d:%d" % [roundi(p.x*100000),roundi(p.z*100000)]
					if not vertices.has(vertex_key): vertices[vertex_key]=field.land_height(p)-field.water_height(p)
					clearances.append(vertices[vertex_key])
				for t in interval:
					var point := center.lerp(end,float(t))
					if triangle_value(Vector2(point.x,point.z),face,clearances) <= CLEARANCE: dry=false; break
				if not dry: break
			# Boundaries overlap; coverage may exceed one, never excuse a missing piece.
			halves[key][target_key] = dry and covered >= 0.99999
	for key in halves:
		for next in halves[key]:
			if halves[key][next] and halves.get(next,{}).get(key,false): allowed[key].append(next)
		allowed[key].sort()
	source_hash = source.content_hash
	diagnostics = {"schema_version":ID,"triangles_examined":triangles,"shared_vertices":vertices.size(),"cells":tiles.size(),"clearance":CLEARANCE,"water_authority":"same clipped PL scalar as terrain_field._triangle","bridge_policy":"not admitted; no implicit bridge or flight permission"}
	return {"ok":true,"diagnostics":diagnostics.duplicate(true)}

static func cross2(a: Vector2,b: Vector2) -> float: return a.x*b.y-a.y*b.x
static func triangle_interval(start: Vector2,end: Vector2,face: Array) -> Array:
	var p: Array = [Vector2(face[0].x,face[0].z),Vector2(face[1].x,face[1].z),Vector2(face[2].x,face[2].z)]
	var orientation: float = signf(cross2(p[1]-p[0],p[2]-p[0]))
	var lo := 0.0; var hi := 1.0
	for i in range(3):
		var edge: Vector2 = p[(i+1)%3]-p[i]
		var f0 := orientation*cross2(edge,start-p[i]); var f1 := orientation*cross2(edge,end-p[i])
		if f0 < -0.00000001 and f1 < -0.00000001: return []
		if absf(f1-f0)<0.000000000001: continue
		var t := -f0/(f1-f0)
		if f1>f0: lo=maxf(lo,t)
		else: hi=minf(hi,t)
		if lo>hi+0.00000001:return []
	return [clampf(lo,0.0,1.0),clampf(hi,0.0,1.0)]
static func triangle_value(point: Vector2,face: Array,values: Array) -> float:
	var a := Vector2(face[0].x,face[0].z); var b := Vector2(face[1].x,face[1].z); var c := Vector2(face[2].x,face[2].z)
	var denominator := cross2(b-a,c-a)
	var v := cross2(point-a,c-a)/denominator; var w := cross2(b-a,point-a)/denominator
	return float(values[0])*(1.0-v-w)+float(values[1])*v+float(values[2])*w
func step(from: Array,to: Array) -> Dictionary:
	var a := Traversal.key(from); var b := Traversal.key(to)
	if not supported.get(a,false) or not supported.get(b,false): return C.fail("NO_DRY_SUPPORT","This anchor has no admitted dry ground; crossing water needs a separately supported action.")
	if not b in allowed.get(a,[]): return C.fail("CROSS_WATER_ASSESSMENT","The exact generated terrain edge is wet or unsupported; no movement was performed.")
	return {"ok":true}
func plan(state: Dictionary,target: Variant,budget: int) -> Dictionary:
	if state.get("generated_world",{}).get("content_hash","")!=source_hash: return C.fail("BUNDLE_MISMATCH","Generated navigation belongs to a different exact source.")
	return Policy.plan(state,"actor_player",target,budget,func(a,b): return step(a,b))
