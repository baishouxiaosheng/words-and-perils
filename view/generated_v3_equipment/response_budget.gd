extends RefCounted
## Pre-RNG admissibility for a scheduled enemy's complete next public request.
## A detached branch preview is not a transaction, intention, damage or RNG draw.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Focus=preload("res://core/focus_contract.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
const Catalog=preload("res://core/source_equipment/catalog.gd")
const Examples=preload("res://view/generated_v3_equipment/assessments.gd")
const MAX_BYTES=65536
# Engine.model_request caps serialized record contents at4096 bytes. 1024
# additional bytes cover the complete memory envelope, observer ID, counters,
# commas and both fact/belief arrays; this is never a budget increase.
const MEMORY_ENVELOPE_BYTES=5120
static func check(state:Dictionary,contract:Dictionary)->Dictionary:
	if state.get("combat_turn",{}).get("phase")!="enemy":return {"ok":true,"required":false}
	if contract.is_empty():return C.fail("ENEMY_REQUEST_CONTRACT","敌方评估契约尚未就绪，行动未裁定。")
	var player:Dictionary=state.actors.actor_player
	var reference={"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":player.hex.duplicate(),"scene_id":player.scene_id}
	var resolved:Dictionary=Focus.new().resolve(reference,state)
	if not resolved.ok:return resolved
	var facts:Dictionary=ModelView.facts(state,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]},resolved.focus)
	if facts.is_empty():return C.fail("ENEMY_REQUEST_CONTEXT","敌方评估资料无法完整形成，行动未裁定。")
	var context={"facts":facts,"attention_focus":ModelView.focus_view(resolved.focus,facts),"goal":Examples.goal("enemy_attack"),"actor_id":Catalog.ENEMY,"text_priority":"explicit_player_text"}
	# A signed64-bit-width action suffix safely bounds the real next_action ID.
	var request={"schema_version":"ai_gm_rebuilt/v1","action_id":state.world_id+":action_9223372036854775807","state_version":state.state_version,"phase":"assessment","context_hash":C.digest(context),"context":context,"contract":contract.duplicate(true)}
	var bounded_bytes:int=C.bytes(request).to_utf8_buffer().size()+MEMORY_ENVELOPE_BYTES
	if bounded_bytes>MAX_BYTES:return C.fail("ENEMY_REQUEST_BUDGET","这个行动可能产生超过64 KiB的敌方评估，尚未锁定或执行；请取消并选择资料更小的行动。")
	return {"ok":true,"required":true,"upper_bound_bytes":bounded_bytes,"budget_bytes":MAX_BYTES,"memory_envelope_bytes":MEMORY_ENVELOPE_BYTES}
