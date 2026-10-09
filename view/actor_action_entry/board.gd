extends "res://view/generated_v3_npc/board.gd"
## Reuses native village, picking, receipt effects and actor motion.
## Does not move the enemy back to its original spawn witness.
const EnemyPresentation=preload("res://view/generated_v3_enemy/presentation.gd")
const EffectRouter=preload("res://view/playable_build/committed_effect_router.gd")
const MovingSupport=preload("res://view/actor_action_entry/moving_support.gd")
const DynamicItemView=preload("res://view/actor_action_entry/item_view.gd")
const DownedLabelCraft=preload("res://view/ui_craft.gd")
const DOWNED_LABEL_OWNER=&"actor_action_entry_owned_downed_label_v1"
var committed_effects:Node3D
var feedback_safe_rect=Rect2()
var enemy_pose:Dictionary={}
var enemy_body_bounds=AABB()
var actor_pose_source_version=-1
func _ready()->void:
	super._ready()
	if is_instance_valid(presentation):remove_child(presentation);presentation.free()
	presentation=EnemyPresentation.new();add_child(presentation)
	committed_effects=EffectRouter.new();add_child(committed_effects)
	committed_effects.motion_presenter=presentation;committed_effects.feedback_camera=camera
	committed_effects.safe_rect_provider=func():return feedback_safe_rect
func set_world(state:Dictionary,animate_changes:bool=false,effects:Array=[])->void:
	if admitted_source==null or not admitted_source.validate_state(state).get("ok",false):load_error="统一行动状态未通过来源校验。";return
	var fit:Dictionary=MovingSupport.fit(admitted_source,state)
	if not fit.get("ok",false):load_error="完整敌人棋子无法在已提交位置显示："+str(fit);return
	if animate_changes:
		var route:Dictionary=MovingSupport.route(admitted_source,world_state,state,effects)
		if not route.get("ok",false):load_error=str(route);return
	# A successful same-source reload must clear an earlier support failure.
	load_error=""
	enemy_pose=fit;enemy_body_bounds=fit.body_bounds
	if actor_pose_source_version!=state.state_version:
		for view in inventory_packs.values():view.pose_cache.clear()
	actor_pose_source_version=state.state_version
	for id in state.generated_world.entity_catalog.entries:
		if not inventory_packs.has(id):
			var view=DynamicItemView.new(id,admitted_source.placement_result.surface);add_child(view);view.bind(self);inventory_packs[id]=view
	presentation.force_reset=not animate_changes
	super.set_world(state,animate_changes,effects)
	if not load_error.is_empty():return
	var id:String=admitted_source.enemy_id
	token_support_metrics[id]=fit.duplicate(true)
	for actor_id in ["actor_player",id]:
		var token:Node3D=token_nodes[actor_id]
		token.scale=Vector3(1,.38 if state.actors[actor_id].health.current<=0 else 1,1)
		_refresh_actor_nameplate(token,str(actor_id),state.actors[actor_id])
	if not animate_changes:committed_effects.reset_to(state)
func _refresh_actor_nameplate(token:Node3D,actor_id:String,actor:Dictionary)->void:
	var downed:bool=actor.health.current<=0
	var existing:Node=token.get_node_or_null("Nameplate")
	var plate:Label3D=existing as Label3D
	if plate==null:
		# Never replace another owner's node or create an auto-renamed duplicate.
		if not downed or existing!=null:return
		plate=Label3D.new();plate.name="Nameplate"
		plate.set_meta(DOWNED_LABEL_OWNER,true)
		plate.font=DownedLabelCraft.font("body")
		plate.font_size=36;plate.pixel_size=.008
		plate.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		plate.modulate=Color.WHITE;plate.outline_size=0
		plate.no_depth_test=false
		token.add_child(plate)
	if plate.get_meta(DOWNED_LABEL_OWNER,false)==true:
		# Only this display-only marker follows death visibility. Existing labels
		# retain their owner's visibility, size and placement policy.
		plate.visible=downed
		if not downed:return
		# Token x/z and the original .38 downed body remain unchanged. Cancel the
		# inherited y flattening for glyphs, and keep .30 above the flattened top.
		var body_y_scale:float=token.scale.y
		plate.scale=Vector3(1.0,1.0/body_y_scale,1.0)
		plate.position=Vector3(0.0,Tokens.height_for(actor_id,actor)+.30/body_y_scale,0.0)
	plate.text=str(actor.name)+( " · 已倒下" if downed else "")

func token_support_pose(center:Vector3,yaw_degrees:float=-16.0)->Dictionary:
	if not enemy_pose.is_empty():
		var p:Vector3=enemy_pose.position
		if Vector2(center.x,center.z).distance_to(Vector2(p.x,p.z))<.000001:return enemy_pose.duplicate(true)
	return super.token_support_pose(center,yaw_degrees)
func present_committed_receipt(receipt:Dictionary,before:Dictionary)->Dictionary:
	return committed_effects.consume(receipt,before,world_state,token_nodes)
func set_feedback_safe_rect(value:Rect2)->void:feedback_safe_rect=value
func set_presentation_safe_rect(value:Rect2)->void:feedback_safe_rect=value

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

