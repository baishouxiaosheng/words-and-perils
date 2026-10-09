extends "res://view/generated_v3_adventure/board.gd"
## Item views are read-only additions to the exact accepted V3 board.
const ItemView=preload("res://view/generated_v3_inventory/item_view.gd")
const SupportSurface=preload("res://core/generated_v3_placement/surface.gd")
var inventory_packs:Dictionary={}
var item_surface:RefCounted
var inventory_pack:Node3D:
	get:return inventory_packs.get("item_travel_bundle")
func _init(source_:RefCounted=null) -> void:super(source_)
func _ready() -> void:
	super._ready()
	if load_error.is_empty():_ensure_item_surface()
func _ensure_item_surface() -> bool:
	if item_surface!=null and item_surface.geometry_hash==admitted_source.identity.geometry_hash:return true
	var candidate:=SupportSurface.new()
	var built:Dictionary=candidate.build(admitted_source.renderer_bundle.ground_mesh,admitted_source.identity.geometry_hash)
	if not built.ok:load_error="行囊显示的地面未通过校验；未放置替代物品。";return false
	item_surface=candidate
	for view in inventory_packs.values():view.surface=item_surface;view.pose_cache.clear()
	return true
func set_world(state:Dictionary,animate_changes:bool=false,committed_effects:Array=[]) -> void:
	super.set_world(state,animate_changes,committed_effects)
	if not load_error.is_empty() or not _ensure_item_surface():return
	var catalog:Dictionary=state.get("generated_world",{}).get("entity_catalog",{}).get("entries",{})
	for id in inventory_packs.keys():
		if not state.items.has(id) or not catalog.has(id):
			var old:Node3D=inventory_packs[id];remove_child(old);old.queue_free();inventory_packs.erase(id)
	var ids:Array=catalog.keys();ids.sort()
	for id in ids:
		if catalog[id].kind!="item":continue
		if not inventory_packs.has(id):
			var view:=ItemView.new(id,item_surface);add_child(view);view.bind(self);inventory_packs[id]=view
		inventory_packs[id].update_state(state)
func pick_focus(point:Vector2) -> Array[Dictionary]:
	var result:Array[Dictionary]=super.pick_focus(point)
	var limit:=INF
	for candidate in result:limit=minf(limit,float(candidate.distance))
	var hits:Array[Dictionary]=[];var nearest:=INF
	for view in inventory_packs.values():
		var hit:Dictionary=view.pick(point,limit+.001)
		if not hit.is_empty():hits.append(hit);nearest=minf(nearest,float(hit.distance))
	# Other opaque item meshes occlude deeper items just as actors/terrain do.
	for hit in hits:
		if float(hit.distance)<=nearest+.001:result.append(hit)
	result.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.distance)<float(b.distance))
	return result
func select_attention(reference_:Dictionary) -> void:
	super.select_attention(reference_)
	for view in inventory_packs.values():view.select(reference_)
func clear_actor_selection() -> void:
	super.clear_actor_selection()
	for view in inventory_packs.values():view.select({})
