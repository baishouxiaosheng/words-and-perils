extends "res://view/generated_v3_npc/board.gd"
## Render one source-bound full-size hostile; receipts alone start transient VFX.
const EnemyPresentation=preload("res://view/generated_v3_enemy/presentation.gd")
const EnemyPlacement=preload("res://view/generated_v3_enemy/placement.gd")
const EffectRouter=preload("res://view/playable_build/committed_effect_router.gd")
const EnemyItemView=preload("res://view/generated_v3_enemy/item_view.gd")
var committed_effects:Node3D
var feedback_safe_rect=Rect2()
func _ready()->void:
	super._ready()
	if is_instance_valid(presentation):remove_child(presentation);presentation.free()
	presentation=EnemyPresentation.new();add_child(presentation)
	committed_effects=EffectRouter.new();add_child(committed_effects)
	committed_effects.motion_presenter=presentation;committed_effects.feedback_camera=camera
	committed_effects.safe_rect_provider=func():return feedback_safe_rect
func set_world(state:Dictionary,animate_changes:bool=false,effects:Array=[])->void:
	if admitted_source==null or not admitted_source.validate_state(state).ok:load_error="遭遇状态未通过校验。";return
	for id in state.generated_world.entity_catalog.entries:
		if not inventory_packs.has(id):
			var view=EnemyItemView.new(id,admitted_source.placement_result.surface);add_child(view);view.bind(self);inventory_packs[id]=view
	presentation.force_reset=not animate_changes
	super.set_world(state,animate_changes,effects)
	if not load_error.is_empty():return
	var id:String=admitted_source.enemy_id
	var witness:Dictionary=admitted_source.enemy_placement_result.placement_witness
	var position_:Vector3=EnemyPlacement.position(witness)
	var token:Node3D=token_nodes[id]
	# Flatten only vertically when downed: never extend beyond proved footprint.
	token.scale=Vector3(1,.38 if state.actors[id].health.current<=0 else 1,1)
	presentation.set_actor_rotation(id,Vector3.ZERO);presentation.reset_actor(id,position_)
	token_support_metrics[id]={"position":position_,"scale":1.0,"full_area_witness":witness.support_witness,"downed_occupied":state.actors[id].health.current<=0}
	var reference:Dictionary={"world_id":state.world_id,"kind":"actor","id":id,"hex":state.actors[id].hex.duplicate(),"scene_id":state.actors[id].scene_id}
	attention_catalog.capture(reference,str(state.actors[id].name)+( " · 已倒下，仍占格" if state.actors[id].health.current<=0 else " · 敌人"),token,true)
	for actor_id in ["actor_player",id]:
		if actor_id=="actor_player":token_nodes[actor_id].scale.y=.38 if state.actors[actor_id].health.current<=0 else 1.0
		var plate:Label3D=token_nodes[actor_id].get_node_or_null("Nameplate") as Label3D
		if plate!=null:plate.text=str(state.actors[actor_id].name)+( " · 已倒下" if state.actors[actor_id].health.current<=0 else "")
	if not animate_changes:committed_effects.reset_to(state)
func present_committed_receipt(receipt:Dictionary,before:Dictionary)->Dictionary:
	return committed_effects.consume(receipt,before,world_state,token_nodes)
func set_feedback_safe_rect(value:Rect2)->void:feedback_safe_rect=value

func _ensure_village(state:Dictionary) -> bool:
	var metadata:Dictionary=state.get("generated_world",{})
	var result:Dictionary=_placement_result();var manifest:Dictionary=result.get("manifest",{})
	if metadata.get("profile")!="generated_v3_village_enemy/v1" or not result.get("ok",false) or manifest.get("placement_hash")!=metadata.get("placement_hash") or manifest.get("profile_id")!=metadata.get("placement_profile") or manifest.get("geometry_hash")!=metadata.get("geometry_hash") or manifest.get("source_hash")!=metadata.get("content_hash") or admitted_source.navigation.get("placement_hash")!=metadata.get("placement_hash"):
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

func set_presentation_safe_rect(value:Rect2)->void:feedback_safe_rect=value

func token_support_pose(center:Vector3,yaw_degrees:float=-16.0)->Dictionary:
	if admitted_source!=null and not admitted_source.enemy_placement_result.is_empty():
		var witness:Dictionary=admitted_source.enemy_placement_result.placement_witness
		var anchor:Vector3=admitted_source.navigation.cell_center(witness.hex)
		if Vector2(anchor.x,anchor.z).distance_to(Vector2(center.x,center.z))<.000001:
			return {"position":EnemyPlacement.position(witness),"rotation":Vector3.ZERO,"full_area_witness":witness.support_witness}
	return super.token_support_pose(center,yaw_degrees)
