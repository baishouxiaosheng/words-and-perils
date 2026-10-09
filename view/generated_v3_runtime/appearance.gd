extends RefCounted
## Continuous display fields from persisted v3 cells. No v2 source regeneration.
## Hues and COLOR/UV2 contract are the existing generated-game palette.
const ID="v3_source_climate_palette/v1"
const ROOT3=1.7320508075688772
var cells: Dictionary
func _init(source: Dictionary) -> void:cells=source.cells
func sample(p: Vector3) -> Dictionary:
	var qf=p.x/ROOT3-p.z/3.0
	var rf=p.z/1.5
	var q=floori(qf);var r=floori(rf);var u=qf-q;var v=rf-r
	var anchors: Array
	var weights: Array
	if u+v<=1.0:
		anchors=[Vector2i(q,r),Vector2i(q+1,r),Vector2i(q,r+1)];weights=[1.0-u-v,u,v]
	else:
		anchors=[Vector2i(q+1,r+1),Vector2i(q,r+1),Vector2i(q+1,r)];weights=[u+v-1.0,1.0-u,1.0-v]
	var total=0.0;var moisture=0.0;var temperature=0.0;var elevation=0.0
	for i in range(3):
		var key="%d,%d"%[anchors[i].x,anchors[i].y]
		if not cells.has(key):continue
		var w=maxf(0.0,float(weights[i]));var c: Dictionary=cells[key]
		total+=w;moisture+=w*float(c.moisture);temperature+=w*float(c.temperature);elevation+=w*float(c.elevation)
	if total<=0.0000001:
		# Only cropped outer hex tips leave the center lattice. Use the nearest
		# existing boundary sample there; never invent a v2 climate/default biome.
		var best=INF;var nearest: Dictionary={}
		for dq in range(-2,3):
			for dr in range(-2,3):
				var key="%d,%d"%[q+dq,r+dr]
				if not cells.has(key):continue
				var c: Dictionary=cells[key];var x=ROOT3*(float(c.q)+float(c.r)*0.5);var z=1.5*float(c.r)
				var distance=(x-p.x)*(x-p.x)+(z-p.z)*(z-p.z)
				if distance<best:best=distance;nearest=c
		if nearest.is_empty():return {"color":Color("749b50").srgb_to_linear(),"weights":Vector2.ZERO,"valid":false}
		moisture=float(nearest.moisture);temperature=float(nearest.temperature);elevation=float(nearest.elevation);total=1.0
	moisture/=total;temperature/=total;elevation/=total
	# V3's own biome thresholds drive the blends; v2's moisture thresholds do not.
	var soil=(1.0-smoothstep(0.16,0.20,moisture))*smoothstep(0.46,0.50,temperature)
	var jungle=smoothstep(0.59,0.65,moisture)*smoothstep(0.57,0.61,temperature)
	var forest=0.45*smoothstep(0.38,0.44,moisture)
	var wetland=0.80*smoothstep(0.76,0.80,moisture)*(1.0-smoothstep(0.28,0.32,elevation))
	var green=maxf(jungle,maxf(forest,wetland))
	var alpine=1.0-smoothstep(0.30,0.34,temperature)
	var palette=Color("749b50").lerp(Color("c9ad7b"),soil).lerp(Color("3f7754"),green)
	return {"color":palette.srgb_to_linear(),"weights":Vector2(soil,alpine),"valid":true,"moisture":moisture,"temperature":temperature}
