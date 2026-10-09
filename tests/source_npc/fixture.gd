extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/source_npc/catalog.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const Focus = preload("res://core/source_npc/focus.gd")
const PublicProjection = preload("res://core/source_npc/projection.gd")
const Conversation = preload("res://core/source_npc/conversation.gd")
const PROFILE := "unit_npc/v1"
static func base() -> Dictionary:
	return {"source_contract":"unit_source/v1","content_hash":"1".repeat(64),"geometry_hash":"2".repeat(64),"runtime_hash":"3".repeat(64),"placement_hash":"4".repeat(64)}
static func descriptor(index: int = 0) -> Dictionary:
	var placement: Dictionary = {"schema_version":"unit_reservation/v1","placement_hash":base().placement_hash,"settlement_id":"village_unit","role":"roadside_guide_"+str(index),"hex":[index+1,0],"position_q40":[0,0,0],"position_scale":1099511627776,"support_witness":{"admitted_by":"unit_fixture","geometry_claim":false}}
	return {"id":Catalog.stable_id(PROFILE,base(),placement,"guide"),"kind":"actor","name":"村口旅人"+str(index),"description":"合成测试人物，不代表地形验证。","role":"guide","faction":"neutral","health":{"current":5,"max":5},"stamina":{"current":5,"max":5},"inventory":[],"statuses":{},"hooks":[],"scene_id":"scene_unit","hex":[index+1,0],"location_revision":0,"placement_witness":placement,"topics":{"directions":{"id":"directions","label":"询问村路","fact_ids":["village_directions_"+str(index)]}},"facts":{"village_directions_"+str(index):{"id":"village_directions_"+str(index),"summary":"测试村口位于相邻地格。","payload":{"entry_hex":[index+1,0],"settlement_id":"village_unit"}}}}
static func world() -> Dictionary:
	var identity: Dictionary = base()
	var desc: Dictionary = descriptor()
	var catalog: Dictionary = Catalog.build(PROFILE,identity,[desc]).catalog
	var metadata: Dictionary = identity.duplicate(true)
	metadata["npc_profile"] = PROFILE; metadata["npc_catalog"] = catalog; metadata["npc_catalog_hash"] = catalog.catalog_hash
	metadata["base_village_runtime_hash"] = identity.runtime_hash
	var player: Dictionary = {"id":"actor_player","name":"旅人","role":"player","faction":"traveler","health":{"current":10,"max":10},"stamina":{"current":10,"max":10},"inventory":[],"statuses":{},"hooks":[],"scene_id":"scene_unit","hex":[0,0]}
	var result: Dictionary = {"schema_version":"ai_gm_world/v1","world_id":"npc_unit_world","state_version":0,"turn":0,"actors":{"actor_player":player,desc.id:Catalog.actor_from_descriptor(desc)},"items":{},"hexes":{},"scenes":{"scene_unit":{"id":"scene_unit","name":"测试地格","layer_id":"surface","hex_ids":[]}},"story_anchors":{},"flags":{},"generated_world":metadata,"npc_state":NPCState.empty(catalog)}
	for i in range(4):
		result.hexes[str(i)+",0"] = {"id":"hex_"+str(i)+"_0","q":i,"r":0,"scene_id":"scene_unit","terrain":"grass","ground_blocked":false,"air_blocked":false,"all_blocked":false,"secret_cell_note":"not_public"}
		result.scenes.scene_unit.hex_ids.append("hex_"+str(i)+"_0")
	return C.normalized(result)
static func npc_id(state: Dictionary) -> String: return state.generated_world.npc_catalog.entries.keys()[0]
static func assessment(state: Dictionary, action_id: String = "action_1") -> Dictionary:
	var id: String = npc_id(state)
	var focus: Dictionary = Focus.resolve(Focus.make_reference(id,state),state).focus
	return {"schema_version":"ai_gm_assessment/v1","action_id":action_id,"state_version":state.state_version,"context_hash":"not_engine_context","narration":"询问路况。","interpretation":"向人物询问登记的村路。","resolver_id":Conversation.ID,"bindings":{"actor_id":"actor_player","target_actor_id":id,"topic_id":"directions"},"components":[{"id":"talk","parameters":{"A":2,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","target"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":state.actors.actor_player.duplicate(true)},{"id":"target","path":"/npc_targets/"+id,"expected":PublicProjection.target_summary(focus)}],"provenance":{"provider":"synthetic-test","live":false,"kind":"model_reply"}}
