extends RefCounted
## Candidate-only adapter. Piggybacks the host action transaction, never rolls or commits.
const C = preload("res://core/status_foundation/canonical.gd")
const SourceProfiles=preload("res://core/status_gameplay/source_profiles.gd")
const Runtime = preload("res://core/status_foundation/runtime.gd")
static var _runtime: RefCounted
static func runtime() -> RefCounted:
 if _runtime==null: _runtime=Runtime.new()
 return _runtime

static func validate_world(world: Dictionary) -> Dictionary:
 if not world.has("status_foundation"): return {"ok":true}
 if world.has("status_areas"):
  if not world.status_areas is Dictionary: return C.fail("STATUS_AREA","Area registry must be a dictionary")
  for area_id in world.status_areas:
   var area: Variant=world.status_areas[area_id]
   if not C.exact_fields(area,["id","scene_id","cell_ids"]) or not area.id is String or area.id!=area_id or not area.scene_id is String or not world.scenes.has(area.scene_id) or not area.cell_ids is Array or area.cell_ids.is_empty() or area.cell_ids.size()>10000: return C.fail("STATUS_AREA","Malformed explicit area membership")
   var seen: Dictionary={}
   for cell_id in area.cell_ids:
    if not cell_id is String or seen.has(cell_id): return C.fail("STATUS_AREA","Invalid or duplicate area cell")
    var cell:=owner(world,"tile",cell_id)
    if cell.is_empty() or cell.scene_id!=area.scene_id: return C.fail("STATUS_AREA","Area member must exist in its scene")
    seen[cell_id]=true
 var checked: Dictionary=runtime().validate(world.status_foundation)
 if not checked.ok: return checked
 for s in world.status_foundation.instances.values():
  var found:=owner(world,s.owner_kind,s.owner_id)
  if found.is_empty(): return C.fail("STATUS_OWNER","Unknown authoritative owner "+s.owner_kind+":"+s.owner_id)
  # Pure runtime supports durability; this narrow installed bridge does not claim it.
  for m in runtime().entries[s.definition_id].mechanics:
   if m.op=="resource_delta" and (s.owner_kind!="actor" or not m.resource in ["health","stamina"]): return C.fail("STATUS_RESOURCE_NOT_INSTALLED","Only actor health/stamina resource events are connected in this candidate")
 return {"ok":true}

static func owner(world: Dictionary,kind: String,id: String) -> Dictionary:
 if kind=="actor": return world.get("actors",{}).get(id,{})
 if kind=="item": return world.get("items",{}).get(id,{})
 if kind=="area":
  # Explicit area registry required. Never silently reinterpret an area as one tile.
  return world.get("status_areas",{}).get(id,{})
 if kind=="tile":
  for cell in world.get("hexes",{}).values():
   if cell.get("id")==id: return cell
  for cells in world.get("scene_hexes",{}).values():
   for cell in cells.values():
    if cell.get("id")==id: return cell
 return {}

static func trusted_context(world: Dictionary,kind: String,id: String) -> Dictionary:
 var body:=owner(world,kind,id)
 var result: Dictionary={"owner_kind":kind,"is_player":kind=="actor" and body.get("role","")=="player"}
 if kind=="tile":
  for k in ["terrain","air_blocked"]:
   if body.has(k): result[k]=body[k]
 # No guesses about heat, wetness, threat, light, contact, or model narrative.
 return result

static func query_actor(world: Dictionary,actor_id: String,context: Dictionary = {}) -> Dictionary:
 if not world.has("status_foundation"): return {"ok":true,"aggregate":Runtime.aggregate([],context),"effects":[]}
 var facts:=trusted_context(world,"actor",actor_id)
 for key in context: facts[key]=context[key]
 return runtime().evaluate(world.status_foundation,"actor",actor_id,facts)

static func permits_intent(world: Dictionary,actor_id: String) -> bool:
 var result:=query_actor(world,actor_id)
 return result.get("ok",false) and result.aggregate.capabilities.get("deliberate_action",true)

static func compact_context(world: Dictionary,actor_id: String) -> Dictionary:
 if not world.has("status_foundation"): return {}
 return runtime().compact_context(world.status_foundation,"actor",actor_id,trusted_context(world,"actor",actor_id),4096)

static func apply(world: Dictionary,patch: Dictionary,internal_hook: bool) -> Dictionary:
 if not world.has("status_foundation"): return C.fail("STATUS_NOT_ENABLED","Legacy worlds stay on legacy status rules")
 if patch.get("type")=="status_v2_event":
  var fields: Array=["type","owner_kind","owner_id","definition_id","change","remaining","clock","parameters","name"]
  if not internal_hook or not C.exact_fields(patch,fields) or not patch.owner_kind is String or not patch.owner_id is String or not patch.definition_id is String or not runtime().entries.has(patch.definition_id) or not patch.change in ["applied","updated","removed"] or not C.integer(patch.remaining) or patch.remaining<0 or patch.remaining>10000 or owner(world,patch.owner_kind,patch.owner_id).is_empty():return C.fail("STATUS_EVENT_PATCH","Only trusted typed status lifecycle events are allowed")
  var d:Dictionary=runtime().entries[patch.definition_id]
  if not patch.name is String or patch.name!=d.name or not patch.clock is String or patch.clock!=d.duration.clock or not runtime().valid_parameters(d,patch.parameters):return C.fail("STATUS_EVENT_PATCH","Event values must match catalog and actual bounded parameters")
  return {"ok":true}
 if patch.get("type")=="status_v2_store":
  if not internal_hook or not C.exact_fields(patch,["type","store"]): return C.fail("STATUS_HOOK_ONLY","Status event result is internal only")
  var candidate: Dictionary=world.duplicate(true); candidate.status_foundation=patch.store
  var checked:=validate_world(candidate)
  if not checked.ok: return checked
  world.status_foundation=patch.store.duplicate(true)
  return {"ok":true}
 if patch.get("type")=="status_v2_world_step":
  if not C.exact_fields(patch,["type","sequence","event_id"]) or not C.integer(patch.sequence) or not Runtime.text(patch.event_id) or patch.sequence!=world.status_foundation.world_clock.sequence+1: return C.fail("STATUS_CLOCK","Explicit trusted world step must advance by one")
  world.status_foundation.world_clock={"sequence":patch.sequence,"event_id":patch.event_id}
  return {"ok":true}
 # A pre-registered program resolver may use these; model schema accepts no patches.
 var result: Dictionary
 if patch.get("type")=="status_v2_apply":
  if not C.exact_fields(patch,["type","definition_id","owner_kind","owner_id","source_id","parameters"]): return C.fail("STATUS_PATCH","Malformed status application")
  if not patch.definition_id is String or not patch.owner_kind is String or not patch.owner_id is String or not patch.source_id is String or not patch.parameters is Dictionary: return C.fail("STATUS_PATCH","Application field types differ")
  result=runtime().apply_status(world.status_foundation,patch.definition_id,patch.owner_kind,patch.owner_id,patch.source_id,patch.parameters)
 elif patch.get("type")=="status_v2_remove":
  if not C.exact_fields(patch,["type","instance_id"]) or not patch.instance_id is String: return C.fail("STATUS_PATCH","Malformed removal")
  result=runtime().remove_status(world.status_foundation,patch.instance_id)
 else: return C.fail("STATUS_PATCH","Unknown status operation")
 if not result.ok: return result
 var probe: Dictionary=world.duplicate(true); probe.status_foundation=result.store
 var valid:=validate_world(probe)
 if not valid.ok: return valid
 world.status_foundation=result.store
 return {"ok":true}

static func freeze(before: Dictionary,candidate: Dictionary,acting_actor_id: String) -> Dictionary:
 if not before.has("status_foundation"): return {"ok":true,"patches":[]}
 var checked:=validate_world(candidate)
 if not checked.ok: return checked
 var initial: Dictionary=before.status_foundation
 var elapsed_steps: int=int(candidate.status_foundation.world_clock.sequence)-int(initial.world_clock.sequence)
 if elapsed_steps<0 or elapsed_steps>1: return C.fail("STATUS_MULTI_WORLD_STEP_UNSUPPORTED","This candidate must reject multiple world steps until ordered event replay is installed; no elapsed step is silently discarded")
 var store: Dictionary=candidate.status_foundation.duplicate(true)
 var owners: Dictionary={}
 for s in store.instances.values(): owners[Runtime.owner_key(s.owner_kind,s.owner_id)]=owner(candidate,s.owner_kind,s.owner_id).duplicate(true)
 var keys: Array=owners.keys(); keys.sort()
 var patches: Array=[]
 for key in keys:
  var split: int=key.find(":"); var kind: String=key.substr(0,split); var id: String=key.substr(split+1)
  var events: Array=[]
  if store.world_clock.sequence>initial.world_clock.sequence: events.append("world_step")
  if kind=="actor" and id==acting_actor_id: events.append("owner_action_end")
  for trigger in events:
   var event: Dictionary={"trigger":trigger,"owner_kind":kind,"owner_id":id,"sequence":int(store.world_clock.sequence) if trigger=="world_step" else int(before.state_version)+1,"event_id":str(store.world_clock.event_id) if trigger=="world_step" else "owner:"+C.digest([before.world_id,int(before.state_version)+1,acting_actor_id]),"context":trusted_context(candidate,kind,id)}
   var result: Dictionary=runtime().advance_event(initial,store,event,owners)
   if not result.ok: return result
   store=result.store; owners=result.owners
   for e in result.effects:
    if e.has("resource") and e.delta!=0:
     var patch: Dictionary={"type":"actor_pool_delta","actor_id":id,"pool":e.resource,"delta":e.delta}
     candidate.actors[id][e.resource].current+=e.delta
     patches.append(patch)
 if C.bytes(store)!=C.bytes(candidate.status_foundation):
  candidate.status_foundation=store
  patches.append({"type":"status_v2_store","store":store.duplicate(true)})
 if before.has("status_gameplay"):
  var ids:Array=initial.instances.keys()
  for instance_id in store.instances:
   if not instance_id in ids:ids.append(instance_id)
  ids.sort()
  for instance_id in ids:
   var old:Dictionary=initial.instances.get(instance_id,{})
   var current:Dictionary=store.instances.get(instance_id,{})
   if C.bytes(old)==C.bytes(current):continue
   var status:Dictionary=old if current.is_empty() else current
   if not SourceProfiles.public_instance(candidate,status) and not SourceProfiles.public_instance(before,status):continue
   var definition:Dictionary=runtime().entries[status.definition_id]
   patches.append({"type":"status_v2_event","owner_kind":status.owner_kind,"owner_id":status.owner_id,"definition_id":status.definition_id,"change":"removed" if current.is_empty() else ("applied" if old.is_empty() else "updated"),"remaining":0 if current.is_empty() else current.remaining,"clock":definition.duration.clock,"parameters":status.parameters.duplicate(true),"name":definition.name})
 return {"ok":true,"patches":patches}
