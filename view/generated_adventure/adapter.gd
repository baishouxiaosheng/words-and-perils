extends "res://view/ai_gm_playtest/adapter.gd"
## Current authority, isolated save namespace. No legacy Game or coast story instantiation.
const Source = preload("res://view/generated_adventure/source.gd")
const GeneratedRule = preload("res://view/generated_adventure/rule.gd")
const GeneratedResolver = preload("res://view/generated_adventure/resolver.gd")
const Examples = preload("res://view/generated_adventure/assessments.gd")
const SAVE_SCHEMA := "generated_adventure_save/v1"
const GENERATED_SAVE := "user://generated_adventure_v1.json"
const MAX_SAVE_BYTES := 24*1024*1024
const MAX_REQUEST_BYTES := 64*1024
const MAX_GOAL_BYTES := 4096
const AUTHOR := Examples.AUTHOR
var source: RefCounted
var admission: Dictionary = {}
var last_feedback := ""
func _init(generated: Dictionary = {}) -> void:
	if not generated.is_empty():admission=_install(generated)
func _install(generated: Dictionary) -> Dictionary:
	var candidate := Source.new()
	var checked:=candidate.admit(generated)
	if not checked.ok:return checked
	var next_engine:=_engine_for(candidate)
	checked=next_engine.ready()
	if not checked.ok:return checked
	source=candidate;engine=next_engine
	return {"ok":true}
func _engine_for(candidate: RefCounted) -> RefCounted:
	var registry := {}
	for kind in ["move","observe","rest"]:
		var resolver:=GeneratedResolver.new(candidate,kind);registry[resolver.resolver_id()]=resolver
	return GMEngine.new(candidate.world,GeneratedRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]})
func ready() -> Dictionary:return engine.ready() if engine!=null else (admission if not admission.is_empty() else C.fail("GENERATED_SOURCE_REQUIRED","No generated source was admitted."))
func state_copy() -> Dictionary:return engine.state_copy() if engine!=null else {}
func begin_intent(goal: String,focus: Dictionary={}) -> Dictionary:
	if not ready().ok:return ready()
	if goal.to_utf8_buffer().size()>MAX_GOAL_BYTES:return C.fail("GENERATED_INTENT_BUDGET","Intent exceeds the bounded generated request budget.")
	if not focus.is_empty() and focus.get("kind") not in supported_focus_kinds():return C.fail("GENERATED_FOCUS_KIND","This source version supports exact actor and tile focus only; environmental objects remain visual.")
	var checked: Dictionary=source.validate_state(state_copy())
	if not checked.ok:return checked
	var result: Dictionary=super.begin_intent(goal,focus)
	if result.ok and C.bytes(result.request).to_utf8_buffer().size()>MAX_REQUEST_BYTES:
		engine.cancel_intent(active_action);active_action=""
		return C.fail("GENERATED_REQUEST_BUDGET","Generated public context exceeded64KiB; the intention was not assessed or rolled.")
	return result
func supported_focus_kinds() -> Array: return ["tile","actor"]
func attention(reference: Dictionary) -> Dictionary:
	if not ready().ok:return ready()
	if not reference.is_empty() and reference.get("kind") not in supported_focus_kinds():return C.fail("GENERATED_FOCUS_KIND","Only exact generated actor/tile focus is currently supported.")
	return super.attention(reference)
func tile_reference(hex: Array) -> Dictionary:
	var state:=state_copy();var key: String="%d,%d"%hex
	if not state.get("hexes",{}).has(key):return {}
	return {"world_id":state.world_id,"kind":"tile","id":state.hexes[key].id,"hex":hex.duplicate(),"scene_id":Source.SCENE}
func sample_goal(kind: String,focus: Dictionary={}) -> String:
	var target: Array=focus.get("hex",state_copy().get("actors",{}).get("actor_player",{}).get("hex",[]))
	return Examples.goal(kind,target)
func fixture_available() -> bool:return phase()=="awaiting_assessment" and Examples.build(request()).ok
func prepare_fixture() -> Dictionary:
	if phase()!="awaiting_assessment":return C.fail("FIXTURE_SCOPE","Submit a complete signed generated example first.")
	var built:=Examples.build(request())
	return engine.prepare_assessment(built.assessment) if built.ok else built
func import_reply(reply: Dictionary) -> Dictionary:
	if not C.safe(reply) or C.bytes(reply).to_utf8_buffer().size()>MAX_REQUEST_BYTES:return C.fail("GENERATED_REPLY_BUDGET","Reply exceeds the bounded generated protocol.")
	if reply.get("narration") is String and reply.narration.to_utf8_buffer().size()>8192:return C.fail("GENERATED_NARRATION_BUDGET","Optional narration exceeds8KiB and was not recorded.")
	return super.import_reply(reply)
func movement_preview(target: Array) -> Dictionary:
	if not ready().ok:return ready()
	var state:=state_copy()
	return source.navigation.plan(state,target,int(state.actors.actor_player.stamina.current))
func frozen_movement_preview() -> Dictionary:
	var action:=action_copy()
	if action.get("assessment",{}).get("resolver_id")!="generated_move_v1":return {}
	for branch in action.branches:
		if not branch.requires.get("move",false):continue
		var route: Array=[action.snapshot.actors.actor_player.hex.duplicate()];var cost:=0
		for patch in branch.patches:
			if patch.type=="actor_move":route.append(patch.hex.duplicate())
			elif patch.type=="actor_pool_delta":cost-=int(patch.delta)
		return {"ok":true,"route":route,"cost":cost,"distance":route.size()-1,"turn_cost":1,"frozen":true}
	return {}
func commit() -> Dictionary:
	var result: Dictionary=super.commit()
	if result.ok:last_feedback="行动已由固定程序提交；位置、体力和观察记录已保存于当前世界。"
	return result
func save_data() -> Dictionary:
	return {"schema_version":SAVE_SCHEMA,"source":source.data.duplicate(true),"engine":engine.save_data()} if ready().ok else {}
func save_file(path: String=GENERATED_SAVE) -> Dictionary:
	if not ready().ok:return ready()
	var encoded:=C.bytes(save_data())
	if encoded.to_utf8_buffer().size()>MAX_SAVE_BYTES:return C.fail("GENERATED_SAVE_BUDGET","Save exceeds the bounded format; original file preserved.")
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return C.fail("SAVE_FAILED","Cannot write generated save temporary file.")
	file.store_string(encoded);file.flush();file.close()
	if DirAccess.rename_absolute(path+".tmp",path)!=OK:return C.fail("SAVE_FAILED","Atomic generated save rename failed.")
	return {"ok":true}
func load_file(path: String=GENERATED_SAVE) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return C.fail("LOAD_FAILED","Cannot read generated adventure save.")
	if file.get_length()>MAX_SAVE_BYTES:file.close();return C.fail("GENERATED_SAVE_BUDGET","Generated save exceeds bounded format.")
	var text_:=file.get_as_text();file.close()
	return load_data(JSON.parse_string(text_))
func load_data(value: Variant) -> Dictionary:
	if not C.exact_fields(value,["schema_version","source","engine"]) or value.schema_version!=SAVE_SCHEMA or not value.source is Dictionary or not value.engine is Dictionary:return C.fail("GENERATED_SAVE_SCHEMA","Only generated_adventure_save/v1 is supported; original and legacy saves remain unchanged.")
	if source!=null and value.source.get("content_hash")!=source.identity.content_hash:return C.fail("GENERATED_SAVE_SOURCE","Save belongs to another source. Open it as a separate generated adventure.")
	var candidate:=Source.new();var checked:=candidate.admit(value.source)
	if not checked.ok:return checked
	checked=candidate.validate_state(value.engine.get("state"))
	if not checked.ok:return checked
	var next_engine:=_engine_for(candidate)
	checked=next_engine.load_data(value.engine)
	if not checked.ok:return checked
	# All frozen branches/RNG/context have been re-derived before publication.
	source=candidate;engine=next_engine;admission={"ok":true};active_action="";last_action="";narration="";last_feedback=""
	for id in value.engine.pending:active_action=id
	var turn_ := -1
	for id in value.engine.receipts:
		if int(value.engine.receipts[id].turn)>turn_:turn_=int(value.engine.receipts[id].turn);last_action=id
	return {"ok":true,"exact_pending":not active_action.is_empty()}
func render_state() -> Dictionary:return source.render_state(state_copy()) if ready().ok else {}
func authority_text() -> String:
	var state:=state_copy()
	if state.is_empty():return "生成世界未通过来源验证"
	var actor: Dictionary=state.actors.actor_player
	return "固定规则 · 回合%d · 坐标(%d,%d) · 体力%d/%d · 已观察%d次\n%s"%[state.turn,actor.hex[0],actor.hex[1],actor.stamina.current,actor.stamina.max,state.flags.observations,last_feedback]
func journal_entries() -> Array:
	var receipts: Array=engine.save_data().receipts.values();receipts.sort_custom(func(a,b):return int(a.turn)<int(b.turn))
	var entries: Array=[]
	for receipt in receipts:entries.append({"title":"第%d次行动"%int(receipt.turn),"text":receipt.goal})
	return entries
