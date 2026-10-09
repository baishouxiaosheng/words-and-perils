extends "res://view/generated_v3_settlement/board.gd"
const BodyBounds=preload("res://view/generated_v3_npc/body_bounds.gd")
var body_bounds=BodyBounds.new()
var cutaway_last:Dictionary={}
const NPCItemView=preload("res://view/generated_v3_npc/item_view.gd")
const NPC_PROFILE="generated_v3_village_npc/v1"
const NPCFocus=preload("res://core/source_npc/focus.gd")
const NPCPlacement=preload("res://view/generated_v3_npc/placement.gd")
const VegetationFocus=preload("res://core/generated_v3_vegetation/focus.gd")
const VegetationView=preload("res://view/generated_v3_vegetation/vegetation_view.gd")
const NPCPicking=preload("res://view/generated_v3_npc/picking.gd")
var npc_picker=NPCPicking.new()
var vegetation_view:Node3D
var vegetation_references:Dictionary={}
var vegetation_signature=""
var npc_reference_cache:Dictionary={}
const PLANT_NAMES={"temperate":"阔叶树","tropical":"热带树","sapling":"幼树","shrub":"灌木","tuft":"草丛","reed":"芦草"}
func _ensure_village(state:Dictionary) -> bool:
	var metadata:Dictionary=state.get("generated_world",{})
	var result:Dictionary=_placement_result();var manifest:Dictionary=result.get("manifest",{})
	if metadata.get("profile")!=NPC_PROFILE or not result.get("ok",false) or manifest.get("placement_hash")!=metadata.get("placement_hash") or manifest.get("profile_id")!=metadata.get("placement_profile") or manifest.get("geometry_hash")!=metadata.get("geometry_hash") or manifest.get("source_hash")!=metadata.get("content_hash") or admitted_source.navigation.get("placement_hash")!=metadata.get("placement_hash"):
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
func _ready() -> void:
	super._ready()
	# Presentation and item nodes keep default priority0, so their current
	# transforms settle before this board refreshes visibility for drawing.
	process_priority=100
func set_world(state:Dictionary,animate_changes:bool=false,committed_effects:Array=[]) -> void:
	if admitted_source==null or not admitted_source.validate_state(state).ok:load_error="村庄冒险进度未通过校验。";return
	for id in state.generated_world.entity_catalog.entries:
		if not inventory_packs.has(id):
			var view=NPCItemView.new(id,admitted_source.placement_result.surface);add_child(view);view.bind(self);inventory_packs[id]=view
	super.set_world(state,animate_changes,committed_effects)
	if not load_error.is_empty():return
	var id:String=admitted_source.npc_id
	if not token_nodes.has(id):load_error="村民模型缺少对应人物身份。";return
	var reference:Dictionary=NPCFocus.make_reference(id,state)
	if reference.is_empty():load_error="村民目标身份无效。";return
	npc_reference_cache=reference.duplicate(true)
	var witness:Dictionary=admitted_source.npc_placement_result.placement_witness
	var position_:Vector3=NPCPlacement.position(witness)
	var token:Node3D=token_nodes[id]
	token.scale=Vector3.ONE*NPCPlacement.SCALE;token.rotation=Vector3.ZERO
	presentation.set_actor_rotation(id,Vector3.ZERO);presentation.reset_actor(id,position_)
	token_support_metrics[id]={"position":position_,"scale":NPCPlacement.SCALE,"full_area_witness":witness.support_witness}
	attention_catalog.capture(reference,str(state.actors[id].name)+" · 村民",token,true)
	var picked:Dictionary=npc_picker.capture([{"id":id,"kind":"actor","hex":state.actors[id].hex,"node":token}])
	if not picked.ok:load_error="村民模型选择几何无效。";return
	if not _ensure_vegetation(state):return
	_refresh_body_cutaway()
	# Ground pack fitting uses the immutable NPC and plant bounds directly;
	# transient selection lifts never move its deterministic cached ground pose.
func _ensure_vegetation(state:Dictionary) -> bool:
	if not admitted_source.features.vegetation:
		if is_instance_valid(vegetation_view):remove_child(vegetation_view);vegetation_view.queue_free()
		vegetation_view=null;vegetation_references.clear();vegetation_signature=""
		return true
	var signature:String=state.generated_world.vegetation_catalog_hash+"/"+state.world_id
	if signature==vegetation_signature and is_instance_valid(vegetation_view):return true
	if is_instance_valid(vegetation_view):remove_child(vegetation_view);vegetation_view.queue_free()
	vegetation_view=VegetationView.new();add_child(vegetation_view)
	var configured:Dictionary=vegetation_view.configure(admitted_source.vegetation_result)
	if not configured.ok:load_error="植被显示未通过来源校验。";return false
	var references:Dictionary=VegetationFocus.references_for_admitted_world(state)
	if not references.get("ok",false):load_error="植被目标目录未通过校验。";return false
	vegetation_references=references.references
	if vegetation_references.size()!=state.generated_world.vegetation_entity_catalog.entries.size():load_error="植被目标目录无效。";return false
	vegetation_signature=signature;return true
func pick_focus(point:Vector2) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if world_state.is_empty() or not load_error.is_empty():return result
	if not _refresh_body_cutaway():return result
	var origin:Vector3=camera.project_ray_origin(point);var direction:Vector3=camera.project_ray_normal(point)
	var terrain:Dictionary=_surface_hit(origin,direction);var limit:float=float(terrain.get("distance",INF))
	var objects:Array[Dictionary]=[]
	for hit in attention_catalog.query(origin,direction,limit+.002):
		if hit.reference.get("kind")=="actor" and hit.reference.id!=admitted_source.npc_id:objects.append(hit)
	for view in inventory_packs.values():
		var hit:Dictionary=view.pick(point,limit+.002)
		if not hit.is_empty():objects.append(hit)
	for hit in npc_picker.query(origin,direction,limit+.002):
		objects.append({"reference":npc_reference_cache.duplicate(true),"label":"守路村民 · 人物","distance":hit.distance,"point":hit.point})
	for hit in village_picker.query(origin,direction,limit+.002):
		var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(hit.point.x,hit.point.z))
		if not cell.get("ok",false):continue
		var selected:Dictionary=_static_pick_reference(str(hit.id),cell.hex)
		if not selected.is_empty():objects.append({"reference":selected.reference.duplicate(true),"label":selected.label+" · "+_kind_label(str(hit.kind)),"distance":hit.distance,"point":hit.point})
	if is_instance_valid(vegetation_view):
		var plant_hits:Array[Dictionary]=vegetation_view.pick(origin,direction,limit+.002)
		if not vegetation_view.report().get("picker",{}).get("last_query",{}).get("complete",false):return []
		for hit in plant_hits:
			if not vegetation_references.has(hit.id):continue
			var d:Dictionary=world_state.generated_world.vegetation_entity_catalog.entries[hit.id]
			objects.append({"reference":vegetation_references[hit.id].duplicate(true),"label":PLANT_NAMES.get(d.asset_id,"植被"),"distance":hit.distance,"point":hit.point})
	var nearest:float=limit
	for hit in objects:nearest=minf(nearest,float(hit.distance))
	for hit in objects:
		if float(hit.distance)<=nearest+OCCLUSION_EPSILON:result.append(hit)
	if not terrain.is_empty() and float(terrain.distance)<=nearest+OCCLUSION_EPSILON:
		var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(terrain.point.x,terrain.point.z))
		if cell.get("ok",false) and world_state.hexes.has(cell.key):
			var tile:Dictionary=world_state.hexes[cell.key]
			result.append({"reference":{"world_id":world_state.world_id,"kind":"tile","id":tile.id,"hex":cell.hex,"scene_id":tile.scene_id},"label":("海面" if terrain.surface=="water" else "地格")+" · (%d,%d)"%cell.hex,"distance":terrain.distance,"point":terrain.point})
	result.sort_custom(func(a,b):return float(a.distance)<float(b.distance) if a.distance!=b.distance else _focus_order(a.reference)<_focus_order(b.reference))
	return result
func select_attention(reference_:Dictionary) -> void:
	super.select_attention(reference_)
	if is_instance_valid(vegetation_view):vegetation_view.select(str(reference_.get("id","")) if reference_.get("kind")=="vegetation" else "")
func clear_actor_selection() -> void:
	super.clear_actor_selection()
	if is_instance_valid(vegetation_view):vegetation_view.select("")
func _process(delta:float) -> void:
	super._process(delta)
	if is_instance_valid(vegetation_view) and is_instance_valid(camera):
		vegetation_view.update_lod(camera);_refresh_body_cutaway()

func _refresh_body_cutaway() -> bool:
	if not is_instance_valid(vegetation_view):return true
	if not token_nodes.has("actor_player"):return _cutaway_failed("旅人显示尚未就绪。")
	var bounds:Array[AABB]=[];var player_parts:Array[AABB]=[]
	if not body_bounds.collect(token_nodes.actor_player,player_parts) or player_parts.is_empty():return _cutaway_failed("旅人模型范围无效。")
	bounds.append(BodyBounds.merged(player_parts))
	for view in inventory_packs.values():
		view.sync_position()
		if not is_instance_valid(view.pack) or not view.pack.visible:continue
		var parts:Array[AABB]=[]
		for node in view.mesh_parts:
			if not body_bounds.collect(node,parts):return _cutaway_failed("行囊模型范围无效。")
		if not parts.is_empty():bounds.append(BodyBounds.merged(parts))
	cutaway_last=vegetation_view.set_body_cutaway_bounds(bounds,true)
	if not cutaway_last.get("ok",false):return _cutaway_failed("植被避让显示未通过校验，请重新读取旅程。")
	return true
func _cutaway_failed(message:String) -> bool:
	load_error=message
	return false
