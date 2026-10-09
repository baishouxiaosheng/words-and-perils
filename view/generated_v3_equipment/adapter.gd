extends "res://view/generated_v3_village/adapter.gd"
## Independent combined village and inventory save/request namespace.
## Save admission exactly reproduces placement before building an overlay.
const EnemySource = preload("res://view/generated_v3_equipment/source.gd")
const EnemyResolver = preload("res://view/generated_v3_equipment/resolver.gd")
const EnemyRule = preload("res://view/generated_v3_equipment/rule.gd")
const EnemyExamples = preload("res://view/generated_v3_equipment/assessments.gd")
const NPCStaticFocus = preload("res://core/source_entities/static_focus.gd")
const ENEMY_SAVE_SCHEMA := "generated_v3_village_equipment_save/v1"
const ENEMY_SAVE := "user://generated_v3_village_equipment_v1.json"
const ENEMY_REQUEST := "user://generated_v3_village_equipment_request_v1.json"
const ENEMY_AUTHOR := EnemyExamples.AUTHOR
const NPCFocus=preload("res://core/source_npc/focus.gd")
const VegetationFocus=preload("res://core/generated_v3_vegetation/focus.gd")
const Conversation=preload("res://core/source_npc/conversation.gd")
var feature_options: Dictionary={"vegetation":false}
# Godot's canonical serializer leaves unsupported C0 controls raw. Reject
# those at this new profile's text boundary; never sanitize frozen intentions.
static func valid_intent_text(goal: String) -> bool:
	for i in goal.length():
		var code=goal.unicode_at(i)
		if code<32 and code not in [9,10,13]:return false
	return true
func begin_intent(goal: String, focus: Dictionary={}) -> Dictionary:
	if enemy_response_available():return C.fail("TURN_ACTOR","敌方回合需先取得它自己的评估，旅人尚不能行动。")
	if not valid_intent_text(goal):return C.fail("NPC_INTENT_TEXT","行动描述包含无法传输的控制字符，请删除后重试；换行和制表符可以保留。")
	return super.begin_intent(goal,focus)
func _install(generated: Dictionary, renderer_profile: String = Source.RENDERER_PROFILE) -> Dictionary:
	var candidate := EnemySource.new()
	var checked := candidate.admit(generated,renderer_profile,null,feature_options)
	if not checked.ok: return checked
	var next_engine := _engine_for(candidate)
	checked = next_engine.ready()
	if not checked.ok: return checked
	_publish(candidate,next_engine,{})
	return {"ok":true,"identity":source.identity.duplicate(true),"admission":gameplay_admission.duplicate(true)}
func _engine_for(candidate: RefCounted) -> RefCounted:
	var registry := {}
	for kind in ["move","observe","rest","drop_item","pickup_item","talk","attack","pickup_blade","equip_weapon"]:
		var resolver := EnemyResolver.new(candidate,kind); registry[resolver.resolver_id()] = resolver
	var installed=GMEngine.new(candidate.world,EnemyRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]})
	candidate.enemy_request_contract={"assessment_schema":GMEngine.ASSESSMENT_SCHEMA,"assessment_required_for_every_intent":true,"attention_is_action":false,"narration_is_facts":false,"calculator":installed.rule_id(),"rule_schema":installed._rule_schema(),"resolver_ids":installed._resolver_ids(),"action_schemas":installed._action_schemas(),"model_reply_is_data_only":true}
	return installed
func default_save_path() -> String: return ENEMY_SAVE
func default_request_path() -> String: return ENEMY_REQUEST
func supported_focus_kinds() -> Array: return ["tile","actor","item","settlement","building","road","vegetation"]
func static_reference(id: String, clicked_hex: Array = []) -> Dictionary:
	return NPCStaticFocus.make_reference(id,state_copy(),clicked_hex) if ready().ok else {}
func sample_goal(kind: String, focus: Dictionary = {}) -> String:
	if kind=="attack" and ready().ok:return EnemyExamples.attack_goal(state_copy().actors.actor_player.equipment.weapon)
	return EnemyExamples.goal(kind,focus.get("hex",state_copy().get("actors",{}).get("actor_player",{}).get("hex",[])))
func fixture_available() -> bool: return phase() == "awaiting_assessment" and EnemyExamples.build(request()).ok
func prepare_fixture() -> Dictionary:
	if phase() != "awaiting_assessment": return C.fail("V3_VILLAGE_EXAMPLE_SCOPE","请先提交完整的探索、行囊或交谈示例。")
	var built := EnemyExamples.build(request())
	return engine.prepare_assessment(built.assessment) if built.ok else built
func save_data() -> Dictionary:
	return {"schema_version":ENEMY_SAVE_SCHEMA,"profile":EnemySource.PROFILE,"source":source.data.duplicate(true),"renderer_profile":source.identity.renderer_profile,"geometry_hash":source.identity.geometry_hash,"identity":source.identity.duplicate(true),"placement_manifest":source.placement_result.manifest.duplicate(true),"features":source.features.duplicate(true),"vegetation_manifest":source.vegetation_result.get("manifest",null),"enemy_placement":source.enemy_placement_result.placement_witness.duplicate(true),"engine":engine.save_data()} if ready().ok else {}
func _check_destination(path: String, request_file: bool = false) -> Dictionary:
	if path.is_empty() or path.get_file() in PROTECTED_FILENAMES + [GENERATED_SAVE.get_file(),V3_REQUEST.get_file(),INVENTORY_SAVE.get_file(),INVENTORY_REQUEST.get_file(),VILLAGE_SAVE.get_file(),VILLAGE_REQUEST.get_file(),"generated_v3_village_npc_v1.json","generated_v3_village_npc_request_v1.json","generated_v3_village_enemy_v1.json","generated_v3_village_enemy_request_v1.json"]: return C.fail("V3_VILLAGE_NAMESPACE","请使用村庄冒险版本的独立文件，旧旅程不会被覆盖。")
	var destination := ProjectSettings.globalize_path(path).simplify_path()
	var counterpart := ProjectSettings.globalize_path(ENEMY_SAVE if request_file else ENEMY_REQUEST).simplify_path()
	if destination == counterpart: return C.fail("V3_VILLAGE_NAMESPACE","请求文件和行囊进度必须分开保存。")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null or file.get_length() > MAX_SAVE_BYTES: return C.fail("V3_VILLAGE_NAMESPACE","无法验证已有文件，未覆盖。")
		var existing: Variant = JSON.parse_string(file.get_as_text()); file.close()
		if request_file:
			if not _is_enemy_request(existing): return C.fail("V3_VILLAGE_NAMESPACE","已有文件不是此版本的请求，未覆盖。")
		elif not existing is Dictionary or existing.get("schema_version") != ENEMY_SAVE_SCHEMA or existing.get("profile") != EnemySource.PROFILE:
			return C.fail("V3_VILLAGE_NAMESPACE","已有文件不属于此村庄冒险版本，未覆盖。")
	return {"ok":true}
static func _is_enemy_request(value: Variant) -> bool:
	if not value is Dictionary or not C.safe(value) or value.get("schema_version") != "ai_gm_rebuilt/v1" or value.get("phase") not in ["assessment","narration"] or not value.get("context") is Dictionary or not value.get("contract") is Dictionary or not value.get("action_id") is String or not value.get("context_hash") is String: return false
	for field in ["state","source","engine","rng","pending","receipts"]:
		if value.has(field): return false
	var tokens: PackedStringArray = value.action_id.split(":action_")
	if tokens.size() != 2 or not tokens[0].begins_with(EnemySource.WORLD_PREFIX) or not Source.valid_hash(tokens[0].trim_prefix(EnemySource.WORLD_PREFIX)) or not tokens[1].is_valid_int() or int(tokens[1]) < 1 or str(int(tokens[1])) != tokens[1]: return false
	if C.digest(value.context) != value.context_hash: return false
	if value.phase == "assessment":
		var facts: Variant = value.context.get("facts")
		if not facts is Dictionary or not facts.get("generated_source") is Dictionary: return false
		return facts.get("world_id") == tokens[0] and facts.generated_source.get("source_contract") == Source.ID and facts.generated_source.get("profile") == EnemySource.PROFILE and facts.generated_source.get("projection_id") == EnemySource.PROJECTION_ID and value.contract.get("calculator") == EnemyRule.ENEMY_ID
	var result: Variant = value.context.get("authoritative_result")
	return value.get("reply_schema") == "ai_gm_narration/v1" and result is Dictionary and result.get("schema_version") == "ai_gm_result/v1" and result.get("action_id") == value.action_id
func load_data(value: Variant) -> Dictionary:
	if not C.exact_fields(value,SAVE_FIELDS+["placement_manifest","features","vegetation_manifest","enemy_placement"]) or not C.safe(value) or value.schema_version != ENEMY_SAVE_SCHEMA or value.profile != EnemySource.PROFILE or not value.source is Dictionary or not value.engine is Dictionary or not value.identity is Dictionary or not value.placement_manifest is Dictionary or not value.features is Dictionary or not value.enemy_placement is Dictionary or not value.renderer_profile is String or not Source.valid_hash(value.geometry_hash): return C.fail("V3_ENEMY_SAVE_SCHEMA","进度不属于此村庄冒险版本；旧进度请在原模式打开。")
	for section in ["pending","receipts"]:
		if value.engine.get(section) is Dictionary:
			for row in value.engine[section].values():
				if row is Dictionary and row.get("goal") is String and (not valid_intent_text(row.goal) or row.goal.to_utf8_buffer().size()>MAX_GOAL_BYTES):return C.fail("NPC_INTENT_TEXT","进度中的行动描述超出此版本的文本范围；现有旅程未改变。")
	if C.bytes(value).to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("V3_SAVE_BUDGET","进度资料过大，现有旅程未改变。")
	if source != null and (value.source.get("content_hash") != source.identity.content_hash or value.renderer_profile != source.identity.renderer_profile): return C.fail("V3_SAVE_SOURCE","这份进度属于另一张地图，请单独打开。")
	var candidate := EnemySource.new()
	var checked := candidate.admit(value.source,value.renderer_profile,value.placement_manifest,value.features,value.vegetation_manifest,value.enemy_placement)
	if not checked.ok: return checked
	if value.geometry_hash != candidate.identity.geometry_hash or C.bytes(value.identity) != C.bytes(candidate.identity): return C.fail("V3_ENEMY_SAVE_IDENTITY","地图、精确地形、村落或行囊目录身份不一致，请使用原版本。")
	checked = candidate.validate_state(value.engine.get("state"))
	if not checked.ok: return checked
	if value.engine.get("receipts") is Dictionary:
		for receipt in value.engine.receipts.values():
			if not receipt is Dictionary: return C.fail("V3_HISTORY","行动记录无效。")
			var focus: Variant = receipt.get("attention_focus",{})
			if focus is Dictionary and focus.get("kind") == "tile":
				var found := false
				for cell in candidate.world.hexes.values():
					if cell.id == focus.get("id"): found = C.bytes(cell) == C.bytes(focus.get("facts")); break
				if not found: return C.fail("V3_HISTORY","历史地格记录与原地图不一致。")
	var next_engine := _engine_for(candidate)
	checked = next_engine.load_data(value.engine)
	if not checked.ok: return checked
	checked = candidate.validate_history(value.engine)
	if not checked.ok: return checked
	_publish(candidate,next_engine,{})
	return {"ok":true,"exact_pending":not active_action.is_empty()}

func movement_preview(target: Array) -> Dictionary:
	return EnemyResolver.local_result(super.movement_preview(target))
func frozen_movement_preview() -> Dictionary:
	var result: Dictionary = super.frozen_movement_preview()
	if not result.is_empty():
		result["placement_hash"] = source.identity.placement_hash
		result["effective_navigation_hash"] = source.identity.effective_navigation_hash
	return result

func npc_reference() -> Dictionary:
	return NPCFocus.make_reference(source.npc_id,state_copy()) if ready().ok else {}
func vegetation_reference(id: String) -> Dictionary:
	return VegetationFocus.make_reference(id,state_copy()) if ready().ok and source.features.vegetation else {}
func _committed_feedback(receipt: Dictionary) -> String:
	var events:Array=[];var state:Dictionary=state_copy()
	for patch_ in receipt.get("patches",[]):
		if patch_.get("type")=="item_relocate" and patch_.get("item_id")=="item_raider_blade":events.append("已取走苦叶短刃，归属记录已更新；倒下敌人的原格仍被占据。")
		elif patch_.get("type")=="item_equip":events.append("已换上"+str(state.items[patch_.item_id].name)+"；原武器仍在行囊中。")
	for event in receipt.get("patches",[]):
		if event.get("type")!="combat_event":continue
		var loss=0
		for patch_ in receipt.patches:
			if patch_.get("type")=="actor_pool_delta" and patch_.get("pool")=="health" and patch_.get("actor_id")==event.target_actor_id:loss-=int(patch_.delta)
		var label:String={"hit":"命中","graze":"擦伤","miss":"未命中"}.get(event.outcome,event.outcome)
		events.append(str(state.actors[event.actor_id].name)+"的近战"+label+("，造成%d点伤害"%loss if loss>0 else "")+"，体力−1。")
		if state.actors[event.target_actor_id].health.current<=0:events.append(str(state.actors[event.target_actor_id].name)+"已倒下。"+("原格仍被占据；靠近后可评估取走他的苦叶短刃，再另行评估换装。" if event.target_actor_id==source.enemy_id else "可读取存档或重新开始。"))
	for patch_ in receipt.get("hook_patches",[]):
		if patch_.get("type")=="actor_pool_delta" and patch_.get("pool")=="health" and patch_.get("delta",0)<0:events.append(str(state.actors[patch_.actor_id].name)+"中毒，生命%d。"%int(patch_.delta))
	if not events.is_empty():
		if state.actors.actor_player.health.current<=0 and not receipt.get("branch_id","").begins_with("attack_"):events.append("旅人因中毒倒下；已提交的物品归属与装备仍然保留。")
		return "".join(events)
	for patch in receipt.get("patches",[]):
		if patch.get("type")=="npc_conversation_record":
			var learned=false
			for fact in patch.facts:
				if fact.first_action_id==patch.action_id:learned=true
			var fact:Dictionary=patch.facts[0]
			var text_:String="村民说：入口在（%d，%d），沿路可到村中（%d，%d）。"%[fact.payload.entry_hex[0],fact.payload.entry_hex[1],fact.payload.village_hex[0],fact.payload.village_hex[1]]
			return text_+("信息已记入旅途笔记。体力−1。" if learned else "首次获知记录保留。体力−1。")
	return super._committed_feedback(receipt)
func restarted() -> RefCounted:
	var candidate=get_script().new()
	if ready().ok:
		candidate.feature_options=source.features.duplicate(true)
		candidate.start_source(source.data,source.identity.renderer_profile)
	return candidate

func learned_notes() -> String:
	if not ready().ok:return "还没有开启村庄冒险。"
	var facts:Dictionary=state_copy().npc_state.learned_facts.actor_player
	if facts.is_empty():return "尚未获知村庄信息。\n\n靠近守路村民，提出交谈并取得评估后，得到的信息会保存在这里。"
	var lines:Array[String]=[]
	for record in facts.values():
		lines.append(str(record.summary))
		lines.append("入口：（%d，%d） · 村中：（%d，%d）"%[record.payload.entry_hex[0],record.payload.entry_hex[1],record.payload.village_hex[0],record.payload.village_hex[1]])
		lines.append(str(record.payload.description))
		lines.append("首次获知：第%d回合 · 守路村民"%(int(record.first_action_start_turn)+1))
	return "\n".join(lines)

func enemy_response_available()->bool:
	return ready().ok and phase()=="idle" and state_copy().combat_turn.phase=="enemy"
func begin_enemy_response()->Dictionary:
	if not enemy_response_available():return C.fail("ENEMY_PHASE","当前没有待评估的敌方行动。")
	var state:Dictionary=state_copy()
	var reference:Dictionary={"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":state.actors.actor_player.hex.duplicate(),"scene_id":state.actors.actor_player.scene_id}
	var result:Dictionary=engine.begin_intent(EnemyExamples.goal("enemy_attack"),reference,source.enemy_id)
	if result.ok:
		active_action=result.request.action_id;narration=""
		if C.bytes(result.request).to_utf8_buffer().size()>MAX_REQUEST_BYTES:
			engine.cancel_intent(active_action);active_action="";return C.fail("V3_REQUEST_BUDGET","敌方评估资料超过64 KiB，尚未执行行动。")
	return result
func enemy_reference()->Dictionary:
	if not ready().ok:return {}
	var state:Dictionary=state_copy();var actor:Dictionary=state.actors[source.enemy_id]
	return {"world_id":state.world_id,"kind":"actor","id":actor.id,"hex":actor.hex.duplicate(),"scene_id":actor.scene_id}
func authority_text()->String:
	var base:String=super.authority_text()
	if not ready().ok:return base
	var state:Dictionary=state_copy();var enemy:Dictionary=state.actors[source.enemy_id]
	return base+"\n持刃拦路者：生命%d/%d · 体力%d/%d · %s"%[enemy.health.current,enemy.health.max,enemy.stamina.current,enemy.stamina.max,"已倒下，仍占据地格" if enemy.health.current<=0 else ("敌方意图待评估" if state.combat_turn.phase=="enemy" else "旅人回合")]
