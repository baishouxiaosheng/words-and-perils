extends RefCounted
## New source-bound profile only. Legacy source, registry and IDs remain untouched.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Base=preload("res://view/generated_v3_enemy/source.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const Policy=preload("res://view/actor_action_profile_v2/policy.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Movement=preload("res://core/status_gameplay/movement.gd")
const Cells=preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Traversal=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const FrozenActorSource=preload("res://view/actor_action_profile_v2/source.gd")
const Domain=preload("res://view/actor_status_profile_v1/domain.gd")
const PROFILE="generated_v3_actor_status/v1"
const PREFIX="generated_v3_actor_status_v1_"
const ACTORS=["actor_player","actor_village_hostile"]
const KINDS=["move","observe","rest","basic_attack","drop_item","pickup_item","equip_item","status_source"]
const CONSUMABLES=["item_poison_vial","item_feather_vial","item_status_antidote"]
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
	# Install before either new-profile marker or immutable fields exist. No v2 save toggle.
	var installed:Dictionary=Content.install_new_world(base.world)
	if not installed.ok:return installed
	var separated:Dictionary=Domain.install(base.world,installed.world)
	if not separated.ok:return separated
	world=separated.world
	# Keep the original weapon resolver and legacy committed-action poison clock.
	# Content's opt-in typed weapon metadata is deliberately not enabled here.
	for item in world.items.values():item.erase("status_on_hit")
	var sources:Dictionary={}
	for id in CONSUMABLES:sources[id]={"quantity":world.items[id].quantity,"profile":world.items[id].status_source.duplicate(true)}
	identity={"schema_version":PROFILE,"base_identity":base.identity.duplicate(true),"profile_hash":code_hash,"actors":ACTORS.duplicate(),"kinds":KINDS.duplicate(),"ordering":"single_enemy_contact_ordinary_eligibility/v2","visibility":"actor_radius3_observable_status/v1","status_targets":ACTORS.duplicate(),"status_sources":sources,"status_source_hash":C.digest(sources),"catalog_hash":Foundation.runtime().catalog_hash,"weapon_poison_clock":"legacy_committed_action","status_delivery":"self_or_source_validated_dry_adjacent/v1","flight_scope":"source_dry_edges_and_safe_landing/v1"}
	identity["status_domain_schema"]=Domain.SCHEMA;identity["status_domain_hash"]=C.digest(world[Domain.FIELD])
	world.world_id=PREFIX+C.digest(identity)
	world["actor_action_identity"]=identity.duplicate(true)
	for id in ACTORS:
		world.flags[observation_key(id)]=0
		world.flags[last_cell_key(id)]=""
	world.story_anchors.anchor_generated_v3_scope.text="Each authorized actor uses the same assessed ordinary action chain. Existing poison, feather and antidote consumables cost their fixed source quantity/stamina; intrinsic landing is assessed and requires a safe supported cell. Another actor must be reachable over a real dry adjacent source edge. Flight retains source dry geometry, actual occupancy and affordable safe landing. Typed poison/flight age only on owner actions; newly applied generations skip the first owner tick, same-generation refresh does not. Original weapon poison keeps its legacy committed-action clock. No new initiative, automatic enemy action, implicit world step, aerial water crossing or fall rescue."
	immutable=fixed_fields(world)
	return validate_state(world)
const EXTRA_DEPENDENCIES=["res://view/actor_status_profile_v1/source.gd", "res://view/actor_status_profile_v1/adapter.gd", "res://view/actor_status_profile_v1/engine.gd", "res://view/actor_status_profile_v1/resolver.gd", "res://view/actor_status_profile_v1/rule.gd", "res://view/actor_status_profile_v1/projection.gd", "res://view/actor_status_profile_v1/decision.gd", "res://view/actor_status_profile_v1/public_status.gd", "res://view/actor_status_profile_v1/history.gd", "res://core/status_gameplay/action.gd"]
static func profile_digest()->String:
	var pins:Dictionary={}
	for path in FrozenActorSource.PROFILE_DEPENDENCIES+EXTRA_DEPENDENCIES+["res://view/actor_status_profile_v1/domain.gd","res://view/actor_status_profile_v1/hooks.gd"]:
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
		if item.id in CONSUMABLES:item.erase("quantity")
	return C.normalized(result)
func validate_state(state:Variant)->Dictionary:
	var checked:Dictionary=World.validate(state)
	if not checked.ok:return checked
	checked=Domain.validate(state)
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
		if item.id in CONSUMABLES and (not C.integer(item.quantity) or item.quantity<0 or item.quantity>int(world.items[item.id].quantity)):return C.fail("ACTOR_STATUS_QUANTITY","Only bounded consumption of the three source-bound starter stacks is permitted; history must prove every change.")
		if item.has("custody_revision") and (not C.integer(item.custody_revision) or item.custody_revision<0 or item.custody_revision>state.turn):return C.fail("ACTOR_PROFILE_CUSTODY","Custody revision exceeds committed history.")
		if item.has("hex") and (item.scene_id!=base.SCENE or not navigation.supported.get("%d,%d"%item.hex,false)):return C.fail("ACTOR_PROFILE_ITEM_POSITION","Ground stack needs source-validated dry support.")
	if state.combat_turn.phase=="enemy" and not Policy.can_schedule(state,navigation):return C.fail("ACTOR_PROFILE_PHASE","Contact order cannot grant an out-of-scope, dead or deliberately blocked enemy slot.")
	var movement_world:Dictionary=Domain.lift(state).world
	for actor_id in ACTORS:
		var actor:Dictionary=movement_world.actors[actor_id]
		if actor.health.current<=0:continue
		if not Movement.can_enter(movement_world,actor,Cells.cell(movement_world,actor.scene_id,actor.hex)):return C.fail("ACTOR_STATUS_POSITION","Current flight/walk mode must respect real cell, air/all blocks, scene clearance and carried load.")
		if Movement.has_flight(movement_world,actor) and not Movement.can_land(movement_world,actor,actor.hex):
			var exit:Dictionary=source_safe_landing(state,actor_id)
			if not exit.ok:return exit
	return {"ok":true}

func source_safe_landing(state:Dictionary,actor_id:String)->Dictionary:
	# Add the same source graph and real occupied-cell guard to the host landing search.
	var lifted:Dictionary=Domain.lift(state)
	if not lifted.ok:return lifted
	var movement_world:Dictionary=lifted.world
	var edge=func(from:Array,to:Array)->Dictionary:
		if Policy.occupied(state,to,actor_id):return C.fail("ACTOR_OCCUPIED","Landing routes cannot cross another combatant's actual cell.")
		return navigation.step(from,to)
	var landing=func(hex:Array)->bool:
		return navigation.supported.get("%d,%d"%hex,false) and not Policy.occupied(state,hex,actor_id) and Movement.can_land(movement_world,movement_world.actors[actor_id],hex)
	return Traversal.safe_landing(movement_world,actor_id,int(state.actors[actor_id].stamina.current),edge,landing)
