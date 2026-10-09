extends "res://view/generated_v3_inventory/board.gd"
## Explicit village+inventory presentation. Source admission owns every fact,
## physical obstruction and save identity; this class only shows and selects it.
const VillageRenderer=preload("res://view/generated_v3_settlement/settlement_view.gd")
const VillagePicking=preload("res://view/generated_v3_settlement/picking.gd")
const StaticFocus=preload("res://core/source_entities/static_focus.gd")
const VillageGlow=preload("res://view/playable_build/attention_glow.gd")
const Canonical=preload("res://core/ai_gm_rebuilt/canonical.gd")
const VILLAGE_PROFILE="generated_v3_village_inventory/v1"
const OCCLUSION_EPSILON=.001
var village_view:Node3D
var village_picker=VillagePicking.new()
var village_glow:Node
var village_nodes:Dictionary={}
var village_labels:Dictionary={}
var collision_subject_ids:Array[String]=[]
var placement_signature:=""
var selected_static_id:=""
var village_last_pick:Dictionary={}
var static_reference_cache:Dictionary={}
func _init(source_:RefCounted=null) -> void:super(source_)
func _ready() -> void:
	super._ready()
	village_glow=VillageGlow.new();add_child(village_glow)
	if load_error.is_empty():_ensure_village(admitted_source.world)
func _placement_result() -> Dictionary:
	if admitted_source==null:return {}
	var value:Variant=admitted_source.get("placement_result")
	return value if value is Dictionary else {}
func _ensure_item_surface() -> bool:
	# Reuse the already-verified placement surface; do not build a second set of
	# ground triangle bins for the same source just to place the travel bundle.
	var result:Dictionary=_placement_result()
	var shared:Variant=result.get("surface")
	if not result.get("ok",false) or not shared is RefCounted or shared.get("geometry_hash")!=admitted_source.identity.geometry_hash:
		load_error="村落与行囊没有共同的已验证地面，未放置替代模型。";return false
	if item_surface==shared:return true
	item_surface=shared
	for view in inventory_packs.values():view.surface=item_surface;view.pose_cache.clear()
	return true
func _ensure_village(state:Dictionary) -> bool:
	var metadata:Dictionary=state.get("generated_world",{})
	var result:Dictionary=_placement_result();var manifest:Dictionary=result.get("manifest",{})
	if metadata.get("profile")!=VILLAGE_PROFILE or not result.get("ok",false) or manifest.get("placement_hash")!=metadata.get("placement_hash") or manifest.get("profile_id")!=metadata.get("placement_profile") or manifest.get("geometry_hash")!=metadata.get("geometry_hash") or manifest.get("source_hash")!=metadata.get("content_hash") or admitted_source.navigation.get("placement_hash")!=metadata.get("placement_hash"):
		load_error="村落显示、来源或实际阻挡规则不属于当前版本。";return false
	var signature:String=str(metadata.placement_hash)+"/"+str(state.get("world_id",""))
	if signature==placement_signature and is_instance_valid(village_view):return true
	_clear_village()
	village_view=VillageRenderer.new();add_child(village_view)
	var installed:Dictionary=village_view.configure(result)
	if not installed.ok:load_error="村落模型未通过实际地面与范围校验；没有显示替代建筑。";_clear_village();return false
	var rows:Array=village_view.selection_nodes()
	var picked:Dictionary=village_picker.capture(rows)
	if not picked.ok:load_error="村落选择几何未通过校验。";_clear_village();return false
	for row in rows:
		var reference:Dictionary=admitted_source.static_reference(str(row.id))
		var resolved:Dictionary=StaticFocus.resolve(reference,state)
		if reference.is_empty() or not resolved.get("ok",false):load_error="村落对象没有对应的已登记身份。";_clear_village();return false
		var descriptor:Dictionary=resolved.focus.facts.descriptor
		# Validate immutable witnesses once at admission, not on the first hover.
		# Roads alone may have two supporting cells; all other out-of-support
		# raw geometry hits are rejected by a cache miss without a full rehash.
		var supports:Array=descriptor.get("supported_hexes",[descriptor.primary_hex])
		for support in supports:
			var ref:Dictionary=admitted_source.static_reference(str(row.id),support)
			var verified:Dictionary=StaticFocus.resolve(ref,state)
			if ref.is_empty() or not verified.get("ok",false):load_error="村落选择位置未通过已登记身份校验。";_clear_village();return false
			static_reference_cache[str(row.id)+"/"+Canonical.bytes(support)]={"reference":ref,"label":str(descriptor.get("name",row.id))}
		village_nodes[row.id]=row.node;village_labels[row.id]=str(descriptor.get("name",row.id))
		# The inherited bag fitter consults these opaque full-model bounds.
		# They are collision witnesses only; static selection below uses raw
		# current-LOD surface arrays, not this catalog's TriangleMesh proxy.
		if row.kind=="building":
			attention_catalog.capture(reference,village_labels[row.id],row.node,false)
			collision_subject_ids.append(str(reference.kind)+":"+str(reference.id))
	placement_signature=signature;route_signature=""
	for view in inventory_packs.values():view.pose_cache.clear()
	set_meta("placement_hash",metadata.placement_hash);set_meta("renderer_id","native_v3_village_inventory/v1")
	return true
func _clear_village() -> void:
	for id in collision_subject_ids:attention_catalog.erase_subject(id)
	collision_subject_ids.clear();village_nodes.clear();village_labels.clear();village_picker.clear();static_reference_cache.clear();placement_signature="";selected_static_id=""
	if is_instance_valid(village_glow):village_glow.clear()
	if is_instance_valid(village_view):remove_child(village_view);village_view.queue_free()
	village_view=null
func set_world(state:Dictionary,animate_changes:bool=false,committed_effects:Array=[]) -> void:
	# Validate before installing any new identity/geometry. Register buildings
	# before the inherited item update so a dropped bag cannot fit inside one.
	if admitted_source==null or not admitted_source.validate_state(state).ok:load_error="村落探索进度未通过校验，当前画面保留。";return
	if not _ensure_village(state):return
	super.set_world(state,animate_changes,committed_effects)
func pick_focus(point:Vector2) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if world_state.is_empty() or not load_error.is_empty():return result
	var origin:Vector3=camera.project_ray_origin(point);var direction:Vector3=camera.project_ray_normal(point)
	var terrain:Dictionary=_surface_hit(origin,direction);var limit:float=float(terrain.get("distance",INF))
	var object_hits:Array[Dictionary]=[]
	# Keep the accepted actor identity/picker behavior. Ignore static proxy hits;
	# their collision registrations exist only for the inherited pack fitter.
	for hit in attention_catalog.query(origin,direction,limit+.002):
		if hit.reference.get("kind")=="actor":object_hits.append(hit)
	for item_view in inventory_packs.values():
		var item_hit:Dictionary=item_view.pick(point,limit+.002)
		if not item_hit.is_empty():object_hits.append(item_hit)
	var raw:Array[Dictionary]=village_picker.query(origin,direction,limit+.002)
	for hit in raw:
		var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(hit.point.x,hit.point.z))
		if not cell.get("ok",false):continue
		var selected:Dictionary=_static_pick_reference(str(hit.id),cell.hex)
		if selected.is_empty():continue
		object_hits.append({"reference":selected.reference.duplicate(true),"label":selected.label+" · "+_kind_label(str(hit.kind)),"distance":hit.distance,"point":hit.point})
	var nearest:float=limit
	for hit in object_hits:nearest=minf(nearest,float(hit.distance))
	for hit in object_hits:
		if float(hit.distance)<=nearest+OCCLUSION_EPSILON:result.append(hit)
	# A building/road and its aggregate may intentionally share the same actual
	# nearest surface. Deeper objects and the hidden ground do not become picks.
	if not terrain.is_empty() and float(terrain.distance)<=nearest+OCCLUSION_EPSILON:
		var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(terrain.point.x,terrain.point.z))
		if cell.get("ok",false) and world_state.hexes.has(cell.key):
			var tile:Dictionary=world_state.hexes[cell.key]
			result.append({"reference":{"world_id":world_state.world_id,"kind":"tile","id":tile.id,"hex":cell.hex,"scene_id":tile.scene_id},"label":("海面" if terrain.surface=="water" else "地格")+" · (%d,%d)"%cell.hex,"distance":terrain.distance,"point":terrain.point})
	result.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.distance)<float(b.distance) if a.distance!=b.distance else _focus_order(a.reference)<_focus_order(b.reference))
	village_last_pick={"raw_static_hits":raw.size(),"visible_candidates":result.size(),"opaque_nearest_distance":nearest if is_finite(nearest) else null,"static_picker":village_picker.last_query.duplicate(true)}
	return result
func _static_pick_reference(id:String,clicked_hex:Array) -> Dictionary:
	# Only immutable static headers/names are cached. Authority resolves the
	# returned reference again; item custody and actor facts are never cached here.
	var key:String=id+"/"+Canonical.bytes(clicked_hex)
	return static_reference_cache.get(key,{})
static func _kind_label(kind:String) -> String:
	return {"building":"建筑","road":"道路","settlement":"村落"}.get(kind,kind)
static func _focus_order(reference:Dictionary) -> int:
	return {"item":0,"actor":1,"building":2,"road":3,"settlement":4,"tile":5}.get(reference.get("kind"),9)
func select_attention(reference_:Dictionary) -> void:
	super.select_attention(reference_)
	selected_static_id=""
	if reference_.get("kind") in ["building","road","settlement"] and village_nodes.has(reference_.get("id")):
		var current:Dictionary=admitted_source.static_reference(str(reference_.id),reference_.get("hex",[]))
		var same:bool=not current.is_empty()
		for field in current:
			if not reference_.has(field) or Canonical.bytes(reference_[field])!=Canonical.bytes(current[field]):same=false;break
		if same:selected_static_id=str(reference_.id)
	if is_instance_valid(village_glow):village_glow.select_actor(selected_static_id,village_nodes)
func clear_actor_selection() -> void:
	super.clear_actor_selection();selected_static_id=""
	if is_instance_valid(village_glow):village_glow.clear()
func _process(_delta:float) -> void:
	if not is_instance_valid(village_view) or not is_instance_valid(camera):return
	village_view.update_lod(camera)
	# The glow is presentation only and is never in the captured picker. Keep
	# its shell on the current LOD mesh without changing the physical envelope.
	if is_instance_valid(village_glow):
		for shell in village_glow.tracked:
			if is_instance_valid(shell) and shell.get_parent() is MeshInstance3D:shell.mesh=shell.get_parent().mesh
func village_report() -> Dictionary:
	return _diagnostic_copy({"placement_hash":get_meta("placement_hash",""),"placement_signature":placement_signature,"load_error":load_error,"selection_ids":village_nodes.keys(),"collision_subject_count":collision_subject_ids.size(),"shared_surface":item_surface==_placement_result().get("surface"),"picker":village_picker.report(),"last_pick":village_last_pick.duplicate(true),"renderer":village_view.report() if is_instance_valid(village_view) else {},"selected_static_id":selected_static_id})

static func _diagnostic_copy(value:Variant) -> Variant:
	# An offscreen projected-size sentinel is not serializable game data. Keep
	# nonfinite renderer diagnostics explicit as null without touching its state.
	if value is float and not is_finite(value):return null
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[key]=_diagnostic_copy(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_diagnostic_copy(item))
		return result
	return value
