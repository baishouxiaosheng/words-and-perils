extends RefCounted
## New source-bound profile only. Legacy source, registry and IDs remain untouched.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Base=preload("res://view/generated_v3_enemy/source.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const Policy=preload("res://view/actor_action_profile_v2/policy.gd")
const PROFILE="generated_v3_actor_actions/v2"
const PREFIX="generated_v3_actor_actions_v2_"
const ACTORS=["actor_player","actor_village_hostile"]
const KINDS=["move","observe","rest","basic_attack","drop_item","pickup_item","equip_item"]
var base:RefCounted
var world:Dictionary={}
var identity:Dictionary={}
var immutable:Dictionary={}
var navigation:RefCounted
func admit(data:Variant,manifest:Variant=null,enemy_placement:Variant=null)->Dictionary:
	var candidate=Base.new()
	var checked:Dictionary=candidate.admit(data,Base.RENDERER_PROFILE,manifest,{"vegetation":false},null,enemy_placement)
	if not checked.ok:return checked
	base=candidate;navigation=base.base_navigation
	var code_hash=profile_digest()
	if code_hash.length()!=64:return C.fail("ACTOR_PROFILE_DEPENDENCY","Missing registered code/content dependency.")
	identity={"schema_version":PROFILE,"base_identity":base.identity.duplicate(true),"profile_hash":code_hash,"actors":ACTORS.duplicate(),"kinds":KINDS.duplicate(),"ordering":"single_enemy_contact_ordinary_eligibility/v2","visibility":"actor_radius3_no_selected_expansion/v1"}
	world=base.world.duplicate(true)
	world.world_id=PREFIX+C.digest(identity)
	world["actor_action_identity"]=identity.duplicate(true)
	world["status_foundation"]=Foundation.runtime().empty()
	for id in ACTORS:
		world.flags[observation_key(id)]=0
		world.flags[last_cell_key(id)]=""
	world.story_anchors.anchor_generated_v3_scope.text="This version permits each authorized traveler or hostile to submit its own ordinary assessed movement, observation, rest, registered weapon attack or actual available whole-stack item action. The same single-enemy order and dry-adjacent contact scope are used; ordinary action eligibility does not require an equipped weapon or attack resources. No automatic enemy attack or initiative rule. The original weapon poison keeps its legacy committed-action clock; typed status owner clocks are separate."
	immutable=fixed_fields(world)
	return validate_state(world)
const PROFILE_DEPENDENCIES=["res://core/ai_gm_rebuilt/basic_actions.gd", "res://core/ai_gm_rebuilt/basic_effects.gd", "res://core/ai_gm_rebuilt/canonical.gd", "res://core/ai_gm_rebuilt/creative_actions.gd", "res://core/ai_gm_rebuilt/creative_control.gd", "res://core/ai_gm_rebuilt/creative_effects.gd", "res://core/ai_gm_rebuilt/engine.gd", "res://core/ai_gm_rebuilt/generic_actions.gd", "res://core/ai_gm_rebuilt/generic_actions_v2.gd", "res://core/ai_gm_rebuilt/generic_effects.gd", "res://core/ai_gm_rebuilt/hooks.gd", "res://core/ai_gm_rebuilt/model_view.gd", "res://core/ai_gm_rebuilt/scene_cells.gd", "res://core/ai_gm_rebuilt/scene_transitions.gd", "res://core/ai_gm_rebuilt/settlement_actions.gd", "res://core/ai_gm_rebuilt/traversal.gd", "res://core/ai_gm_rebuilt/traversal_policy.gd", "res://core/ai_gm_rebuilt/world.gd", "res://core/campaign_memory/journal.gd", "res://core/capability_catalog/catalog.gd", "res://core/focus_contract.gd", "res://core/generated_v3_placement/asset_catalog.gd", "res://core/generated_v3_placement/navigation_overlay.gd", "res://core/generated_v3_placement/planner.gd", "res://core/generated_v3_placement/surface.gd", "res://core/generated_v3_vegetation/assets.gd", "res://core/generated_v3_vegetation/catalog.gd", "res://core/generated_v3_vegetation/focus.gd", "res://core/generated_v3_vegetation/planner.gd", "res://core/generated_v3_vegetation/projection.gd", "res://core/source_enemy/catalog.gd", "res://core/source_entities/catalog.gd", "res://core/source_entities/focus.gd", "res://core/source_entities/projection.gd", "res://core/source_entities/static_catalog.gd", "res://core/source_entities/static_focus.gd", "res://core/source_entities/static_projection.gd", "res://core/source_equipment/catalog.gd", "res://core/source_npc/catalog.gd", "res://core/source_npc/conversation.gd", "res://core/source_npc/focus.gd", "res://core/source_npc/projection.gd", "res://core/source_npc/state.gd", "res://core/status_foundation/canonical.gd", "res://core/status_foundation/catalog.gd", "res://core/status_foundation/engine_bridge.gd", "res://core/status_foundation/runtime.gd", "res://core/status_gameplay/content.gd", "res://core/status_gameplay/movement.gd", "res://core/status_gameplay/source_profiles.gd", "res://core/world_generation_contract.gd", "res://core/world_generation_v3/generator.gd", "res://core/world_generation_v3/tiny_remnant_cleanup.gd", "res://core/world_generation_validation.gd", "res://core/world_generator.gd", "res://data/catalog.json", "res://shared/scene_feature_layout.gd", "res://view/actor_action_profile_v2/adapter.gd", "res://view/actor_action_profile_v2/decision.gd", "res://view/actor_action_profile_v2/engine.gd", "res://view/actor_action_profile_v2/history.gd", "res://view/actor_action_profile_v2/hooks.gd", "res://view/actor_action_profile_v2/policy.gd", "res://view/actor_action_profile_v2/projection.gd", "res://view/actor_action_profile_v2/resolver.gd", "res://view/actor_action_profile_v2/rule.gd", "res://view/actor_action_profile_v2/scheduler.gd", "res://view/actor_action_profile_v2/source.gd", "res://view/channel_index.gd", "res://view/chess_tokens.gd", "res://view/ecology_preview/vegetation_meshes.gd", "res://view/ecology_preview/vegetation_surface.gdshader", "res://view/generated_adventure/projection.gd", "res://view/generated_inventory/item_focus.gd", "res://view/generated_inventory/projection.gd", "res://view/generated_inventory/resolver.gd", "res://view/generated_v3_adventure/assessments.gd", "res://view/generated_v3_adventure/projection.gd", "res://view/generated_v3_adventure/resolver.gd", "res://view/generated_v3_adventure/source.gd", "res://view/generated_v3_enemy/assessments.gd", "res://view/generated_v3_enemy/history.gd", "res://view/generated_v3_enemy/navigation.gd", "res://view/generated_v3_enemy/placement.gd", "res://view/generated_v3_enemy/policy.gd", "res://view/generated_v3_enemy/projection.gd", "res://view/generated_v3_enemy/resolver.gd", "res://view/generated_v3_enemy/response_budget.gd", "res://view/generated_v3_enemy/source.gd", "res://view/generated_v3_equipment/projection.gd", "res://view/generated_v3_inventory/assessments.gd", "res://view/generated_v3_inventory/projection.gd", "res://view/generated_v3_inventory/resolver.gd", "res://view/generated_v3_inventory/source.gd", "res://view/generated_v3_npc/assessments.gd", "res://view/generated_v3_npc/placement.gd", "res://view/generated_v3_npc/projection.gd", "res://view/generated_v3_npc/resolver.gd", "res://view/generated_v3_npc/source.gd", "res://view/generated_v3_rivers/projection.gd", "res://view/generated_v3_runtime/appearance.gd", "res://view/generated_v3_runtime/geometry.gd", "res://view/generated_v3_runtime/ground.gdshader", "res://view/generated_v3_runtime/navigation.gd", "res://view/generated_v3_runtime/structured_hex_builder.gd", "res://view/generated_v3_runtime/water.gdshader", "res://view/generated_v3_village/projection.gd", "res://view/generated_v3_village/source.gd", "res://view/integrated_ecology_world/performance_variant/whole_canopies.gd", "res://view/mesh_chunks.gd", "res://view/miniature_materials.gd", "res://view/playable_build/authored_assessments.gd", "res://view/playable_build/basic_examples.gd", "res://view/playable_build/composite_examples.gd", "res://view/playable_build/creative_content.gd", "res://view/playable_build/creative_examples.gd", "res://view/playable_build/effect_examples.gd", "res://view/playable_build/entity_catalog.gd", "res://view/playable_build/navigation.gd", "res://view/playable_build/physical_water_queries.gd", "res://view/playable_build/rule_release_v1.gd", "res://view/playable_build/scene_adapters.gd", "res://view/playable_build/settlement_content.gd", "res://view/playable_build/settlement_examples.gd", "res://view/playable_build/story.gd", "res://view/playable_build/world.gd", "res://view/playable_build/world_bundle.gd", "res://view/shaders/miniature_range.gdshader", "res://view/status_gameplay/details.gd", "res://view/terrain_field.gd", "res://view/terrain_profiles.gd"]
static func profile_digest()->String:
	var pins:Dictionary={}
	for path in PROFILE_DEPENDENCIES:
		var hash_=FileAccess.get_sha256(path)
		if hash_.length()!=64:return ""
		pins[path]=hash_
	return C.digest(pins)
static func observation_key(id:String)->String:return "actor_observations_"+id
static func last_cell_key(id:String)->String:return "actor_last_cell_"+id
static func fixed_fields(state:Dictionary)->Dictionary:
	var result=state.duplicate(true)
	for field in ["state_version","turn","combat_turn","flags","status_foundation"]:result.erase(field)
	for id in ACTORS:
		var a:Dictionary=result.actors[id]
		for field in ["hex","inventory","equipment","statuses"]:a.erase(field)
		a.health.erase("current");a.stamina.erase("current")
	for item in result.items.values():
		for field in ["owner_actor_id","hex","scene_id","custody_revision"]:item.erase(field)
	return C.normalized(result)
func validate_state(state:Variant)->Dictionary:
	var checked:Dictionary=World.validate(state)
	if not checked.ok:return checked
	state=C.normalized(state)
	if base==null or not C.exact_fields(state,world.keys()) or not C.exact_fields(state.actors,world.actors.keys()) or not C.exact_fields(state.items,world.items.keys()) or C.bytes(fixed_fields(state))!=C.bytes(immutable):return C.fail("ACTOR_PROFILE_IDENTITY","World or capabilities differ from this new source-bound profile.")
	if state.state_version!=state.turn or state.combat_turn.enemy_actor_id!=ACTORS[1] or state.combat_turn.round>state.turn:return C.fail("ACTOR_PROFILE_TURN","Invalid committed encounter counters.")
	if not C.exact_fields(state.flags,world.flags.keys()):return C.fail("ACTOR_PROFILE_FLAGS","Observation owners cannot be added or removed.")
	for id in ACTORS:
		var actor:Dictionary=state.actors[id]
		if "patrol" in actor.hooks:return C.fail("ACTOR_PROFILE_PATROL","Explicit actors cannot also receive a patrol displacement in this profile.")
		for status_id in actor.statuses:
			var status:Dictionary=actor.statuses[status_id]
			if status_id!="weapon_poison" or status.kind!="poison" or status.remaining_turns not in [1,2] or status.magnitude!=1:return C.fail("ACTOR_LEGACY_STATUS","Only the original bounded blade poison is installed in the legacy namespace.")
		var key="%d,%d"%actor.hex
		if not navigation.supported.get(key,false) or not navigation.allowed.has(key) or Policy.occupied(state,actor.hex,id):return C.fail("ACTOR_PROFILE_POSITION","Actor must occupy its own supported unoccupied dry cell.")
		var count:Variant=state.flags[observation_key(id)];var last:Variant=state.flags[last_cell_key(id)]
		if not C.integer(count) or count<0 or count>state.turn or not last is String or (count==0)!=last.is_empty() or (not last.is_empty() and not state.hexes.has(last)):return C.fail("ACTOR_PROFILE_OBSERVATION","Observation record must belong to its actual actor.")
	for key in ["observations","last_observed_cell"]:
		if state.flags[key]!=world.flags[key]:return C.fail("ACTOR_PROFILE_LEGACY_FLAGS","Old player-only observation namespace is frozen.")
	for item in state.items.values():
		if item.has("custody_revision") and (not C.integer(item.custody_revision) or item.custody_revision<0 or item.custody_revision>state.turn):return C.fail("ACTOR_PROFILE_CUSTODY","Custody revision exceeds committed history.")
		if item.has("hex") and (item.scene_id!=base.SCENE or not navigation.supported.get("%d,%d"%item.hex,false)):return C.fail("ACTOR_PROFILE_ITEM_POSITION","Ground stack needs source-validated dry support.")
	if state.combat_turn.phase=="enemy" and not Policy.can_schedule(state,navigation):return C.fail("ACTOR_PROFILE_PHASE","Contact order cannot grant an out-of-scope, dead or deliberately blocked enemy slot.")
	return {"ok":true}
