extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/source_npc/catalog.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const Focus = preload("res://core/source_npc/focus.gd")
const PublicProjection = preload("res://core/source_npc/projection.gd")
const Conversation = preload("res://core/source_npc/conversation.gd")
const Release = preload("res://view/playable_build/rule_release_v1.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Fixture = preload("res://tests/source_npc/fixture.gd")
var checks: int = 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("NPC_CORE_FAIL ",label)
func range_ok(_state: Dictionary, _actor: String, _target: String) -> bool: return true
func range_denied(_state: Dictionary, _actor: String, _target: String) -> Dictionary: return {"ok":false}
func run() -> void:
	var state: Dictionary = Fixture.world(); var id: String = Fixture.npc_id(state)
	var initial: String = C.bytes(state)
	check(Catalog.validate_world(state).ok and NPCState.validate_world(state).ok,"source-neutral catalog and state validate")
	check(NPCState.validate_world({"actors":{},"generated_world":{}}).ok,"genuinely unrelated world unchanged")
	check(not NPCState.validate_world({"npc_state":{},"generated_world":false}).ok,"malformed metadata fails closed without method dispatch")
	for metadata in [null,"legacy_scalar",[]]:
		check(NPCState.validate_world({"generated_world":metadata}).ok,"unrelated legacy metadata does not gain NPC restrictions")
		check(not NPCState.validate_world({"npc_state":{},"generated_world":metadata}).ok,"typed NPC with malformed metadata fails closed")
	check(not NPCState.validate_world({"generated_world":{"npc_profile":"partial"}}).ok,"partial NPC profile marker rejected")
	check(not NPCState.validate_world({"generated_world":{"npc_catalog_hash":"a".repeat(64)}}).ok,"partial NPC hash marker rejected")
	check(World.validate(state).ok,"full common actor shape passes existing World validator")
	check(state.actors[id].inventory == [] and state.actors[id].statuses == {} and state.actors[id].hooks == [],"NPC actor keeps item-compatible common containers")
	var ref: Dictionary = Focus.make_reference(id,state)
	var focus: Dictionary = Focus.resolve(ref,state).focus
	var view: Dictionary = PublicProjection.frozen_focus(focus,["id","scene_id","q","r","terrain"])
	check(ref.kind == "actor" and ref.location_revision == 0 and ref.contact_revision == 0,"identity distinct from zero location and contact revision")
	check(Focus.validate_historical(focus,state).is_empty(),"exact new historical witness accepted")
	check(view.facts.descriptor.offered_topics[0].id == "directions" and not view.facts.descriptor.has("facts") and not view.facts.descriptor.has("topics"),"public projection offers topics without finite hidden answers")
	check(not view.facts.supporting_cell.has("secret_cell_note"),"supporting cell explicit whitelist")
	check(C.bytes(state) == initial,"catalog and focus operations are read-only")
	for field in Focus.REF_FIELDS:
		var bad: Dictionary = ref.duplicate(true)
		bad[field] = 900 if field in ["location_revision","contact_revision"] else "forged"
		check(not Focus.resolve(bad,state).ok,"reference rejects forged "+field)
	var as_float: Dictionary = ref.duplicate(true); as_float.hex = [1.0,0.0]; as_float.location_revision = 0.0; as_float.contact_revision = 0.0
	check(Focus.resolve(as_float,state).ok,"float JSON reference accepted against integral world")
	var float_world: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(Focus.resolve(ref,float_world).ok,"integral reference accepted against float JSON world")
	check(Focus.validate_historical(JSON.parse_string(JSON.stringify(focus)),state).is_empty(),"float historical snapshot is numerically canonical")
	var built: Dictionary = Catalog.build(Fixture.PROFILE,Fixture.base(),[Fixture.descriptor(),Fixture.descriptor(1)])
	check(built.ok and built.catalog.entries.size() == 2,"reusable catalog supports distinct stable NPCs")
	check(not Catalog.build(Fixture.PROFILE,Fixture.base(),[Fixture.descriptor(),Fixture.descriptor()]).ok,"catalog duplicate IDs rejected before insertion")
	for unsafe in ["bad/id","bad~id","bad id","坏身份",""]:
		var descriptor_: Dictionary = Fixture.descriptor(); descriptor_.id = unsafe
		check(not Catalog.build(Fixture.PROFILE,Fixture.base(),[descriptor_]).ok,"unsafe pointer ID rejected "+unsafe)
	var collision: Dictionary = Fixture.base(); collision.entity_catalog = {"entries":{id:{}}}
	check(not Catalog.build(Fixture.PROFILE,collision,[Fixture.descriptor()]).ok,"NPC item-catalog collision rejected")
	collision = Fixture.base(); collision.static_entity_catalog = {"entries":{id:{}}}
	check(not Catalog.build(Fixture.PROFILE,collision,[Fixture.descriptor()]).ok,"NPC static-catalog collision rejected")
	var bad_world: Dictionary = state.duplicate(true); bad_world.items[id] = {}
	check(not Catalog.validate_world(bad_world).ok,"NPC live item collision rejected")
	bad_world = state.duplicate(true); bad_world.generated_world.base_village_runtime_hash = "5".repeat(64)
	check(not Catalog.validate_world(bad_world).ok,"base village runtime mismatch rejected")
	var bad_catalog: Dictionary = state.generated_world.npc_catalog.duplicate(true)
	bad_catalog.entries[id].placement_witness.hex = [2,0]; bad_catalog.entries[id].hex = [2,0]
	bad_catalog.erase("catalog_hash"); bad_catalog.catalog_hash = C.digest(bad_catalog)
	check(Catalog.validate(bad_catalog).ok,"generic transport catalog permits same logical NPC with changed pose; Source authenticates placement")
	check(bad_catalog.catalog_hash != state.generated_world.npc_catalog.catalog_hash,"pose change changes immutable catalogue hash")
	var moved: Dictionary = Fixture.descriptor()
	moved.hex = [2,0]; moved.placement_witness.hex = [2,0]
	moved.placement_witness.position_q40 = [1,2,3]
	moved.placement_witness.support_witness = {"changed_support":true}
	check(Catalog.stable_id(Fixture.PROFILE,Fixture.base(),moved.placement_witness,moved.role) == id,"stable NPC identity excludes pose and support input")
	var moved_catalog: Dictionary = Catalog.build(Fixture.PROFILE,Fixture.base(),[moved])
	check(moved_catalog.ok and moved_catalog.catalog.catalog_hash != state.generated_world.npc_catalog.catalog_hash,"same role-slot NPC pose retains ID while catalogue binds exact pose")
	check(not Catalog.build(Fixture.PROFILE,Fixture.base(),[Fixture.descriptor(),moved]).ok,"duplicate immutable role slot rejects even when poses differ")
	bad_catalog = state.generated_world.npc_catalog.duplicate(true); bad_catalog.entries[id].topics.directions.fact_ids = ["invented_fact"]
	bad_catalog.erase("catalog_hash"); bad_catalog.catalog_hash = C.digest(bad_catalog)
	check(not Catalog.validate(bad_catalog).ok,"rehashing unknown topic fact cannot mint finite answer")
	var resolver: RefCounted = Conversation.new(range_ok)
	var assessment: Dictionary = Fixture.assessment(state)
	var plan: Dictionary = resolver.freeze(state,assessment)
	check(plan.ok and plan.branches.size() == 2,"one assessed cooperative talk produces complete branches")
	check(resolver.check_policy(state,assessment).policies.talk == "safe_direct","trusted preconditions assign direct policy")
	var release: RefCounted = Release.new({Conversation.ID:resolver})
	var calculated: Dictionary = release.calculate(state,assessment)
	check(calculated.ok and calculated.checks[0].method == "direct_success" and calculated.checks[0].roll_max == 0,"unchanged release calculator uses no random domain")
	check(plan.branches[1].patches[0] == {"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-1},"legitimate talk costs exact one stamina via World patch")
	var patch: Dictionary = plan.branches[1].patches[1]
	check(patch.action_start_turn == 0 and patch.facts[0].first_action_start_turn == 0,"first proof uses explicit action-start turn")
	var public_effect: Dictionary = NPCState.public_effect(patch,state)
	check(public_effect.newly_learned_facts.size() == 1 and public_effect.already_known_fact_ids.is_empty(),"truthful first-learning public effect")
	for field in ["summary","payload","fact_id","npc_id","topic_id","catalog_hash","evidence_hash","first_action_id","first_action_start_turn"]:
		var bad: Dictionary = patch.duplicate(true)
		bad.facts[0][field] = {"forged":true} if field == "payload" else (23 if field == "first_action_start_turn" else "forged")
		check(not NPCState.apply(state,bad).ok and C.bytes(state) == initial,"invalid fact rejects without mutation "+field)
	var wrong: Dictionary = assessment.duplicate(true); wrong.bindings.topic_id = "invented_topic"
	check(not resolver.freeze(state,wrong).ok and C.bytes(state) == initial,"model cannot choose unknown topic")
	wrong = assessment.duplicate(true); wrong.components[0].parameters["fact_id"] = 1
	check(not resolver.freeze(state,wrong).ok,"arbitrary effect parameter rejected")
	wrong = assessment.duplicate(true); wrong.fact_refs[1].expected.contact_revision = 99
	check(not resolver.freeze(state,wrong).ok,"target witness forgery rejected")
	check(not Conversation.new(range_denied).freeze(state,assessment).ok,"adjacent geometric distance cannot bypass blocked edge")
	check(not Conversation.new().freeze(state,assessment).ok,"missing trusted navigation callback fails closed")
	bad_world = state.duplicate(true); bad_world.actors.actor_player.stamina.current = 0
	check(not resolver.freeze(bad_world,Fixture.assessment(bad_world)).ok,"stamina refusal changes no authority")
	bad_world = state.duplicate(true); bad_world.actors.actor_player.hex = [3,0]
	check(not resolver.freeze(bad_world,Fixture.assessment(bad_world)).ok,"distant target rejected before permissive callback")
	bad_world = state.duplicate(true); bad_world.actors.actor_player.health = "invalid"
	check(not resolver.freeze(bad_world,assessment).ok,"malformed actor pools fail closed without authority change")
	var fingerprint_before: String = C.digest(resolver.attempt_fingerprint(state,assessment))
	check(NPCState.apply(state,patch).ok,"first talk typed patch applies")
	check(NPCState.validate_world(state).ok and NPCState.stable(Fixture.world(),state),"pre-increment branch validates at original turn")
	check(not NPCState.validate_committed(state).ok,"uncommitted prospective contact cannot load as committed save")
	check(not NPCState.apply(state,patch).ok,"same patch cannot double contact")
	state.turn += 1; state.state_version += 1; state.actors.actor_player.stamina.current -= 1
	check(NPCState.validate_committed(state).ok,"incremented committed contact passes strict save validator")
	var first_fact: Dictionary = state.npc_state.learned_facts.actor_player.values()[0].duplicate(true)
	check(not Focus.resolve(ref,state).ok,"contact invalidates old live reference")
	check(Focus.validate_historical(focus,state).is_empty() and C.bytes(PublicProjection.frozen_focus(focus,["id","scene_id","q","r","terrain"])) == C.bytes(view),"history keeps original contact facts after current contact changes")
	assessment = Fixture.assessment(state,"action_2")
	plan = resolver.freeze(state,assessment)
	check(plan.ok and C.digest(resolver.attempt_fingerprint(state,assessment)) != fingerprint_before,"repeat conversation has legitimate changed contact fingerprint")
	var repeat_patch: Dictionary = plan.branches[1].patches[1]
	check(C.bytes(repeat_patch.facts[0]) == C.bytes(first_fact),"repeat reuses exact immutable first proof")
	public_effect = NPCState.public_effect(repeat_patch,state)
	check(public_effect.newly_learned_facts.is_empty() and public_effect.already_known_fact_ids.size() == 1,"repeat report distinguishes known from newly learned")
	check(NPCState.apply(state,repeat_patch).ok,"second conversation applies")
	state.turn += 1; state.state_version += 1; state.actors.actor_player.stamina.current -= 1
	check(state.npc_state.contacts[id].revision == 2 and state.npc_state.contacts[id].conversation_count == 2 and state.actors.actor_player.stamina.current == 8 and state.turn == 2,"two legitimate talks count twice and cost two stamina/turns")
	check(state.npc_state.learned_facts.actor_player.size() == 1 and C.bytes(state.npc_state.learned_facts.actor_player.values()[0]) == C.bytes(first_fact),"first proof survives repeats with no duplicate fact")
	check(NPCState.public_effect(patch).newly_learned_facts.size() == 1 and NPCState.public_effect(repeat_patch).newly_learned_facts.is_empty(),"historical effect uses frozen first-action proof after later repeat")
	check(C.bytes(NPCState.public_effect(patch,{})) == C.bytes(NPCState.public_effect(patch,state)),"historical effect ignores mutable context entirely")
	var forged: Dictionary = focus.duplicate(true); forged.facts.public_state.revision = 1
	check(not Focus.validate_historical(forged,state).is_empty(),"historical contact witness revision mismatch rejected")
	var report: Dictionary = {"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"source-neutral NPC core; no physical admission or native rendering claim"}
	DirAccess.make_dir_recursive_absolute("res://artifacts/source_npc")
	var file: FileAccess = FileAccess.open("res://artifacts/source_npc/core_report.json",FileAccess.WRITE); file.store_string(C.bytes(report)); file.close()
	print("SOURCE_NPC_CORE ",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
