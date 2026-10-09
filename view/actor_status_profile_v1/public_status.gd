extends RefCounted
## Observer visibility is checked by the caller. No private/full-store projection.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const Details=preload("res://view/status_gameplay/details.gd")
const Profiles=preload("res://core/status_gameplay/source_profiles.gd")
const SOURCES={"item_poison_vial":"poison_vial","item_feather_vial":"feather_vial"}
const ACTORS=["actor_player","actor_village_hostile"]
const View=preload("res://core/ai_gm_rebuilt/model_view.gd")

static func observable_application(patch:Dictionary)->bool:
	if patch.get("type")!="status_v2_apply" or patch.get("owner_kind")!="actor" or not patch.get("owner_id") in ACTORS or not SOURCES.has(patch.get("source_id")):return false
	var source:Dictionary=Profiles.profile(SOURCES[patch.source_id])
	return patch.get("definition_id")==source.definition_id and C.bytes(patch.get("parameters"))==C.bytes(source.parameters)

static func matches_event(instance:Dictionary,event:Dictionary)->bool:
	return instance.get("owner_kind")==event.get("owner_kind") and instance.get("owner_id")==event.get("owner_id") and instance.get("definition_id")==event.get("definition_id") and C.bytes(instance.get("parameters"))==C.bytes(event.get("parameters"))

static func visible_event(before:Dictionary,after:Dictionary,observer_id:String,event:Dictionary)->bool:
	if event.get("owner_kind")!="actor" or not event.get("owner_id") in ACTORS:return false
	for world in [before,after]:
		if not world.get("actors",{}).has(observer_id) or not world.actors.has(event.owner_id):continue
		var observer:Dictionary=world.actors[observer_id];var actor:Dictionary=world.actors[event.owner_id]
		if observer.scene_id!=actor.scene_id or preload("res://core/ai_gm_rebuilt/basic_effects.gd")._distance(observer.hex,actor.hex)>3:continue
		for instance in world.get("status_foundation",{}).get("instances",{}).values():
			if observable(world,instance) and matches_event(instance,event):return true
	return false

static func recorded_event(receipt:Dictionary,event:Dictionary)->bool:
	# Only evidence inside this exact immutable receipt. Unknown/removed provenance
	# is omitted rather than guessed from a later world or source inventory.
	var observed_target=event.get("owner_id")==receipt.get("actor_id")
	for patch in receipt.get("patches",[]):
		if observable_application(patch) and matches_event(patch,event):observed_target=true
	if not observed_target:return false
	for patch in receipt.get("hook_patches",[]):
		if patch.get("type")!="status_v2_store":continue
		for instance in patch.get("store",{}).get("instances",{}).values():
			var application:Dictionary=instance.duplicate(true);application["type"]="status_v2_apply"
			# A refresh apply patch alone is insufficient: refresh retains old source_id.
			if observable_application(application) and matches_event(instance,event):return true
	return false

static func historical_focus(focus:Dictionary)->Dictionary:
	var detached:Dictionary=focus.duplicate(true)
	if detached.get("kind")=="actor" and detached.get("facts") is Dictionary:
		# Legacy frozen focus has display rows but no typed source provenance.
		# Retain historical non-status facts, never backfill from current state.
		detached.facts.erase("statuses");detached.facts.erase("status_details")
		var result:Dictionary=View.historical_focus(detached,{"npc_secret_allowlist":[],"public_flag_ids":[]})
		result.facts["status_details"]={"available":false,"rows":[]}
		return result
	return View.historical_focus(detached,{"npc_secret_allowlist":[],"public_flag_ids":[]})

static func public_legacy_patch(patch:Dictionary)->bool:
	if not patch.get("actor_id") in ACTORS or patch.get("status_id")!="weapon_poison":return false
	if patch.get("type")=="actor_status_remove":return true
	var status:Variant=patch.get("status")
	return C.exact_fields(status,["id","kind","remaining_turns","magnitude"]) and status.id=="weapon_poison" and status.kind=="poison" and status.remaining_turns in [1,2] and status.magnitude==1

static func observable(world:Dictionary,instance:Dictionary)->bool:
	if instance.get("owner_kind")!="actor" or not instance.get("owner_id") in ACTORS:return false
	var source_id:Variant=instance.get("source_id","")
	if not SOURCES.has(source_id) or not world.get("items",{}).has(source_id):return false
	var source:Dictionary=Profiles.profile(SOURCES[source_id])
	return C.bytes(world.items[source_id].get("status_source"))==C.bytes(source) and instance.get("definition_id")==source.definition_id and C.bytes(instance.get("parameters"))==C.bytes(source.parameters)

static func details(world:Dictionary,actor_id:String)->Dictionary:
	if not world.get("actors",{}).has(actor_id):return {"available":false,"rows":[]}
	var rows:Array=[]
	var actor:Dictionary=world.actors[actor_id]
	for instance in world.get("status_foundation",{}).get("instances",{}).values():
		if instance.get("owner_id")!=actor_id or not observable(world,instance):continue
		var definition:Dictionary=Foundation.runtime().entries[instance.definition_id]
		var row:Dictionary=Details._foundation_row(definition,instance,actor)
		if instance.definition_id=="flight":row.effects=["飞行状态已生效；移动仍须通过原来源干地边、实际占格、空中/全域障碍、禁飞、净空、负重与安全落脚检查", "本原型不开放跨水、坠落、抓攀或救援终态"]
		rows.append(row)
	# Only this profile's fixed legacy blade-poison record is observable.
	if actor_id in ACTORS:
		var legacy:Dictionary={"statuses":{}}
		if actor.get("statuses",{}).has("weapon_poison"):legacy.statuses.weapon_poison=actor.statuses.weapon_poison.duplicate(true)
		rows.append_array(Details._legacy_details(legacy).rows)
	Details._sort_rows(rows)
	return C.normalized({"available":true,"rows":rows})

static func compact(world:Dictionary,actor_id:String)->Dictionary:
	# Small public explanation only. Neither instance/source IDs nor the catalog/store
	# are copied into the model's actor context, including for its own action.
	return {"schema_version":"actor_observable_status_context/v1","readonly":true,"observer_id":actor_id,"details":details(world,actor_id),"new_application":"skip first owner tick","refresh":"same generation ticks on its owner's action","legacy_weapon_poison":"each committed action","world_step":"explicit trusted event only"}
