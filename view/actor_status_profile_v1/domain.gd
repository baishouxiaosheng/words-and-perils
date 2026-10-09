extends RefCounted
## Versioned sidecar reconciles exact catalog NPC identity with typed status views.
## No Source preload, no new clock, no weakening of the original NPC validator.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const SCHEMA="actor_status_domain/v1"
const FIELD="actor_status_domain"

static func install(base:Dictionary,installed:Dictionary)->Dictionary:
	if base.has(FIELD) or base.has("status_gameplay") or not installed.has("status_gameplay"):return C.fail("ACTOR_STATUS_DOMAIN","Domain installs only from the original new Base and its explicit status content result.")
	var state:Dictionary=installed.duplicate(true);var extensions:Dictionary={}
	for id in base.get("generated_world",{}).get("npc_catalog",{}).get("entries",{}):
		if base.actors[id].has("status_body") or base.actors[id].has("status_actions"):return C.fail("ACTOR_STATUS_DOMAIN","The immutable NPC already owns an extension field.")
		extensions[id]={"actor_id":id,"status_body":state.actors[id].status_body.duplicate(true),"status_actions":state.actors[id].status_actions.duplicate(true)}
		state.actors[id]=base.actors[id].duplicate(true)
	state[FIELD]={"schema_version":SCHEMA,"config":state.status_gameplay.duplicate(true),"npc_extensions":extensions}
	state.erase("status_gameplay")
	var checked:Dictionary=validate(state)
	return {"ok":true,"world":C.normalized(state)} if checked.ok else checked

static func lift(state:Dictionary)->Dictionary:
	if not C.safe(state):return C.fail("ACTOR_STATUS_DOMAIN","Canonical domain input must be finite typed data.")
	# This is a structural projection guard, not full-state/Source validation: hook
	# candidates have not had their turn counters advanced yet.
	if state.has("status_gameplay") or not C.exact_fields(state.get(FIELD),["schema_version","config","npc_extensions"]):return C.fail("ACTOR_STATUS_DOMAIN","Canonical status domain has an old marker or wrong exact fields.")
	var domain:Dictionary=state[FIELD]
	if domain.schema_version!=SCHEMA or not domain.config is Dictionary or not domain.npc_extensions is Dictionary:return C.fail("ACTOR_STATUS_DOMAIN","Versioned domain configuration and extensions must be objects.")
	var entries:Variant=state.get("generated_world",{}).get("npc_catalog",{}).get("entries")
	if not entries is Dictionary or not C.exact_fields(domain.npc_extensions,entries.keys()):return C.fail("ACTOR_STATUS_DOMAIN","NPC capability extensions must match the exact immutable catalog membership.")
	var view:Dictionary=state.duplicate(true);view["status_gameplay"]=domain.config.duplicate(true)
	for id in entries:
		var extension:Variant=domain.npc_extensions[id]
		if not state.get("actors",{}).has(id) or state.actors[id].has("status_body") or state.actors[id].has("status_actions"):return C.fail("ACTOR_STATUS_DOMAIN","Canonical NPC cannot carry inline status extensions.")
		if not C.exact_fields(extension,["actor_id","status_body","status_actions"]) or extension.actor_id!=id or not extension.status_body is Dictionary or not extension.status_actions is Dictionary:return C.fail("ACTOR_STATUS_DOMAIN","NPC extension actor binding or exact typed fields differ.")
		view.actors[id]["status_body"]=extension.status_body.duplicate(true);view.actors[id]["status_actions"]=extension.status_actions.duplicate(true)
	return {"ok":true,"world":view}

static func restore(view:Dictionary)->Dictionary:
	if not C.safe(view):return C.fail("ACTOR_STATUS_DOMAIN","Synthetic view must be finite typed data.")
	if not C.exact_fields(view.get(FIELD),["schema_version","config","npc_extensions"]) or not view.has("status_gameplay"):return C.fail("ACTOR_STATUS_DOMAIN","Status view lost its explicit configuration.")
	var domain:Dictionary=view[FIELD]
	if domain.schema_version!=SCHEMA or not domain.config is Dictionary or not domain.npc_extensions is Dictionary:return C.fail("ACTOR_STATUS_DOMAIN","Synthetic domain has malformed typed fields.")
	if C.bytes(view.status_gameplay)!=C.bytes(domain.config):return C.fail("ACTOR_STATUS_DOMAIN","Synthetic configuration changed during a trusted operation.")
	var state:Dictionary=view.duplicate(true);state.erase("status_gameplay")
	for id in domain.npc_extensions:
		var extension:Variant=domain.npc_extensions[id]
		if not C.exact_fields(extension,["actor_id","status_body","status_actions"]) or extension.actor_id!=id or not extension.status_body is Dictionary or not extension.status_actions is Dictionary:return C.fail("ACTOR_STATUS_DOMAIN","Synthetic extension cannot change its actor binding or field types.")
		if not view.actors.has(id):return C.fail("ACTOR_STATUS_DOMAIN","An operation removed a catalog NPC.")
		for field in ["status_body","status_actions"]:
			if C.bytes(view.actors[id].get(field))!=C.bytes(extension[field]):return C.fail("ACTOR_STATUS_DOMAIN","A synthetic NPC capability changed; it cannot be silently discarded.")
			state.actors[id].erase(field)
	var checked:Dictionary=lift(state)
	return {"ok":true,"world":state} if checked.ok else checked

static func validate(state:Dictionary)->Dictionary:
	var checked:Dictionary=World.validate(state)
	if not checked.ok:return checked
	checked=lift(state)
	if not checked.ok:return checked
	return Content.validate(checked.world)

static func apply(state:Dictionary,patch:Variant,internal_hook:bool=false)->Dictionary:
	if not patch is Dictionary or patch.get("type")!="actor_move":return World.apply(state,patch,internal_hook)
	var lifted:Dictionary=lift(state)
	if not lifted.ok:return lifted
	var checked:Dictionary=World.apply(lifted.world,patch,internal_hook)
	if not checked.ok:return checked
	var restored:Dictionary=restore(lifted.world)
	if not restored.ok:return restored
	var expected:Dictionary=state.duplicate(true)
	expected.actors[patch.actor_id].hex=lifted.world.actors[patch.actor_id].hex.duplicate()
	if C.bytes(expected)!=C.bytes(restored.world):return C.fail("ACTOR_STATUS_MOVE","Validated movement changed fields beyond the actor hex.")
	state.actors[patch.actor_id].hex=expected.actors[patch.actor_id].hex.duplicate()
	return {"ok":true}
