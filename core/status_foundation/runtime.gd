extends RefCounted
## Pure, deterministic typed status runtime. No RNG, narrative parser or second turn engine.
const C = preload("res://core/status_foundation/canonical.gd")
const Catalog = preload("res://core/status_foundation/catalog.gd")
const SCHEMA := "status_state/v1"
const MAX_INSTANCES := 256
const MAX_OWNER_INSTANCES := 64
var entries: Dictionary = {}
var catalog_hash := ""
var initialization: Dictionary = {}

func _init(compiled: Dictionary = {}) -> void:
 var loaded := Catalog.load_default() if compiled.is_empty() else compiled
 if not loaded.get("ok",false): initialization=loaded; return
 entries=loaded.entries.duplicate(true); catalog_hash=loaded.catalog_hash

func ready() -> Dictionary:
 return {"ok":true} if initialization.is_empty() else initialization.duplicate(true)

func empty() -> Dictionary:
 return {"schema_version":SCHEMA,"catalog_hash":catalog_hash,"revision":0,"instances":{},"last_events":{},"world_clock":{"sequence":0,"event_id":"initial"}}

static func owner_key(kind: String,id: String) -> String:
 return kind+":"+id

func validate(store: Variant) -> Dictionary:
 if not ready().ok: return ready()
 if not C.exact_fields(store,["schema_version","catalog_hash","revision","instances","last_events","world_clock"]) or not C.safe(store) or not store.schema_version is String or store.schema_version!=SCHEMA or not store.catalog_hash is String or store.catalog_hash!=catalog_hash or not C.integer(store.revision) or store.revision<0 or not store.instances is Dictionary or store.instances.size()>MAX_INSTANCES or not store.last_events is Dictionary or store.last_events.size()>2048: return C.fail("STATUS_STATE","Malformed or incompatible status store")
 if not C.exact_fields(store.world_clock,["sequence","event_id"]) or not C.integer(store.world_clock.sequence) or store.world_clock.sequence<0 or not text(store.world_clock.event_id): return C.fail("STATUS_CLOCK","Invalid world clock")
 var counts: Dictionary={}
 var groups: Dictionary={}
 var active_kinds: Dictionary={}
 for id in store.instances:
  var s: Variant=store.instances[id]
  if not C.exact_fields(s,["id","definition_id","owner_kind","owner_id","source_id","parameters","remaining","stacks","generation"]) or not s.id is String or s.id!=id or not text(id) or not s.definition_id is String or not entries.has(s.definition_id): return C.fail("STATUS_INSTANCE","Malformed stable status instance")
  var d: Dictionary=entries[s.definition_id]
  if not s.owner_kind is String or not s.owner_kind in d.scopes or not text(s.owner_id) or not text(s.source_id) or not valid_parameters(d,s.parameters) or not C.integer(s.remaining) or s.remaining<1 or s.remaining>d.duration.ticks or not C.integer(s.stacks) or s.stacks<1 or s.stacks>d.stacking.max_stacks or not C.integer(s.generation) or s.generation<1 or s.generation>store.revision: return C.fail("STATUS_INSTANCE",str(id))
  var key:=owner_key(s.owner_kind,s.owner_id)
  counts[key]=counts.get(key,0)+1
  if counts[key]>MAX_OWNER_INSTANCES: return C.fail("STATUS_OWNER_LIMIT",key)
  var group_key: String=key+":"+s.definition_id
  if not groups.has(group_key): groups[group_key]=[]
  if s.source_id in groups[group_key]: return C.fail("STATUS_STACK_STATE","Duplicate same-source active status")
  groups[group_key].append(s.source_id)
  var permitted: int=int(d.stacking.max_stacks) if d.stacking.mode=="independent" else 1
  if groups[group_key].size()>permitted: return C.fail("STATUS_STACK_STATE","Too many active instances for stacking mode")
  if not active_kinds.has(key): active_kinds[key]=[]
  for other in active_kinds[key]:
   if other in d.conflicts or s.definition_id in entries[other].conflicts: return C.fail("STATUS_CONFLICT_STATE","Conflicting saved statuses")
  active_kinds[key].append(s.definition_id)
 for k in store.last_events:
  if not k is String or k.is_empty() or k.length()>320 or not C.exact_fields(store.last_events[k],["sequence","event_id","event_hash"]) or not C.integer(store.last_events[k].sequence) or store.last_events[k].sequence<1 or not text(store.last_events[k].event_id) or not text(store.last_events[k].event_hash): return C.fail("STATUS_EVENT","Invalid event watermark")
 return {"ok":true}

static func text(value: Variant) -> bool:
 return value is String and not value.is_empty() and value.length()<=128

func valid_parameters(d: Dictionary,params: Variant) -> bool:
 if not params is Dictionary or params.size()!=d.parameters.size(): return false
 for key in d.parameters:
  if not params.has(key) or not Catalog.number(params[key]) or params[key]<d.parameters[key].min or params[key]>d.parameters[key].max: return false
 return true

func defaults(id: String) -> Dictionary:
 var result: Dictionary={}
 if not entries.has(id): return result
 for p in entries[id].parameters: result[p]=entries[id].parameters[p].default
 return result

func apply_status(store: Dictionary,definition_id: String,owner_kind: String,owner_id: String,source_id: String,parameters: Dictionary = {}) -> Dictionary:
 var valid:=validate(store)
 if not valid.ok: return valid
 if store.revision>=C.LIMIT: return C.fail("STATUS_COUNTER_EXHAUSTED","Status revision cannot advance safely")
 if not entries.has(definition_id): return C.fail("STATUS_UNKNOWN",definition_id)
 var d: Dictionary=entries[definition_id]
 if not owner_kind in d.scopes or not text(owner_id) or not text(source_id): return C.fail("STATUS_OWNER","Invalid scope or trusted source identity")
 var params:=defaults(definition_id)
 for key in parameters:
  if not params.has(key): return C.fail("STATUS_PARAMETER",str(key))
  params[key]=parameters[key]
 if not valid_parameters(d,params): return C.fail("STATUS_PARAMETER","Parameters outside authored ranges")
 var key:=owner_key(owner_kind,owner_id)
 var matches: Array=[]
 var owned:=0
 for s in store.instances.values():
  if owner_key(s.owner_kind,s.owner_id)!=key: continue
  owned+=1
  if s.definition_id in d.conflicts or definition_id in entries[s.definition_id].conflicts: return C.fail("STATUS_CONFLICT",s.definition_id)
  if s.definition_id==definition_id: matches.append(s)
 matches.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.id<b.id)
 var copy: Dictionary=store.duplicate(true)
 copy.revision+=1
 var existing: Dictionary={}
 if d.stacking.mode=="independent":
  for s in matches:
   if s.source_id==source_id: existing=s
  if existing.is_empty() and matches.size()>=d.stacking.max_stacks: return C.fail("STATUS_STACK_LIMIT",definition_id)
 elif not matches.is_empty(): existing=matches[0]
 if existing.is_empty():
  if owned>=MAX_OWNER_INSTANCES or store.instances.size()>=MAX_INSTANCES: return C.fail("STATUS_LIMIT","Active status budget exceeded")
  var instance_id: String="status_"+C.digest([owner_kind,owner_id,definition_id,source_id,copy.revision]).substr(0,24)
  if copy.instances.has(instance_id): return C.fail("STATUS_INSTANCE_ID_COLLISION","New stable status ID already exists")
  copy.instances[instance_id]={"id":instance_id,"definition_id":definition_id,"owner_kind":owner_kind,"owner_id":owner_id,"source_id":source_id,"parameters":params,"remaining":int(d.duration.ticks),"stacks":1,"generation":copy.revision}
  return {"ok":true,"store":copy,"instance_id":instance_id,"change":"applied"}
 var current: Dictionary=copy.instances[existing.id]
 current.remaining=maxi(current.remaining,int(d.duration.ticks))
 if d.stacking.mode=="replace": current.parameters=params; current.source_id=source_id
 elif d.stacking.mode=="intensity":
  if current.stacks<d.stacking.max_stacks:
   current.parameters.intensity=clampf(current.parameters.intensity+params.intensity,d.parameters.intensity.min,d.parameters.intensity.max)
   current.stacks+=1
 return {"ok":true,"store":copy,"instance_id":existing.id,"change":"stacked" if d.stacking.mode=="intensity" else "refreshed"}

func remove_status(store: Dictionary,instance_id: String) -> Dictionary:
 var valid:=validate(store)
 if not valid.ok: return valid
 if store.revision>=C.LIMIT: return C.fail("STATUS_COUNTER_EXHAUSTED","Status revision cannot advance safely")
 if not store.instances.has(instance_id): return C.fail("STATUS_MISSING",instance_id)
 var copy: Dictionary=store.duplicate(true)
 copy.instances.erase(instance_id); copy.revision+=1
 return {"ok":true,"store":copy}

func intensity(store: Dictionary,kind: String,id: String,definition_id: String) -> float:
 var total:=0.0
 for s in store.instances.values():
  if s.owner_kind==kind and s.owner_id==id and s.definition_id==definition_id: total+=float(s.parameters.get("intensity",1))
 return total

func conditions_match(conditions: Array,context: Dictionary,store: Dictionary,kind: String,id: String) -> bool:
 for p in conditions:
  var actual: Variant
  if p.has("status"): actual=intensity(store,kind,id,p.status)
  else:
   if not context.has(p.fact): return false
   actual=context[p.fact]
  match p.op:
   "eq":
    if typeof(actual)!=typeof(p.value) and not (Catalog.number(actual) and Catalog.number(p.value)): return false
    if actual!=p.value: return false
   "ne":
    if typeof(actual)!=typeof(p.value) and not (Catalog.number(actual) and Catalog.number(p.value)): return false
    if actual==p.value: return false
   "gte":
    if not Catalog.number(actual) or actual<p.value: return false
   "lte":
    if not Catalog.number(actual) or actual>p.value: return false
   "in":
    if not actual in p.value: return false
 return true

static func scalar(value: Variant,params: Dictionary) -> float:
 return float(params[value.param])*float(value.scale) if value is Dictionary else float(value)

func evaluate(store: Dictionary,kind: String,id: String,context: Dictionary = {},trigger: String = "query",eligible_ids: Variant = null) -> Dictionary:
 var valid:=validate(store)
 if not valid.ok: return valid
 if not kind in Catalog.SCOPES or not text(id) or not trigger in Catalog.TRIGGERS or not Catalog.valid_context(context): return C.fail("STATUS_CONTEXT","Invalid trusted query context")
 if eligible_ids!=null:
  if not eligible_ids is Array: return C.fail("STATUS_ELIGIBILITY","Eligibility must be null or typed instance IDs")
  for eligible_id in eligible_ids:
   if not eligible_id is String: return C.fail("STATUS_ELIGIBILITY","Eligibility must contain strings")
 var effects: Array=[]
 var ids: Array=store.instances.keys(); ids.sort()
 var facts: Dictionary=C.normalized(context); facts["owner_kind"]=kind
 for instance_id in ids:
  var s: Dictionary=store.instances[instance_id]
  if s.owner_kind!=kind or s.owner_id!=id or (eligible_ids!=null and not instance_id in eligible_ids): continue
  var d: Dictionary=entries[s.definition_id]
  if not conditions_match(d.conditions,facts,store,kind,id): continue
  for m in d.mechanics:
   if m.trigger!=trigger or not conditions_match(m.conditions,facts,store,kind,id): continue
   var effect: Dictionary=m.duplicate(true)
   effect.erase("conditions"); effect["instance_id"]=instance_id; effect["definition_id"]=s.definition_id
   for key in Catalog.NUMERIC.get(m.op,[]): effect[key]=scalar(m[key],s.parameters)
   effects.append(effect)
 return {"ok":true,"readonly":true,"effects":effects,"aggregate":aggregate(effects,facts)}

static func aggregate(effects: Array,context: Dictionary) -> Dictionary:
 context=C.normalized(context) if C.safe(context) else {}
 var result: Dictionary={"check_modifiers":{},"action_cost":{"flat":0.0,"multiplier_bps":10000.0},"movement":{},"passability":{},"perception":{},"behavior_weights":{},"properties":{},"damage":{"flat":0.0,"multiplier_bps":10000.0},"capabilities":{},"barriers":[]}
 for e in effects:
  match e.op:
   "check_modifier":
    if e.check=="any" or (context.get("check") is String and e.check==context.check):
     result.check_modifiers[e.check]=result.check_modifiers.get(e.check,0.0)+e.value
   "action_cost":
    if e.action=="any" or (context.get("action") is String and e.action==context.action):
     result.action_cost.flat+=e.flat; result.action_cost.multiplier_bps+=e.multiplier_bps-10000
   "damage_modifier":
    if e.damage_type=="any" or (context.get("damage_type") is String and e.damage_type==context.damage_type):
     result.damage.flat+=e.flat; result.damage.multiplier_bps+=e.multiplier_bps-10000
   "movement": result.movement[e.mode]=result.movement.get(e.mode,true) and e.allow
   "capability": result.capabilities[e.capability]=result.capabilities.get(e.capability,true) and e.allow
   "passability":
    result.passability[e.layer]=result.passability.get(e.layer,false) or e.blocked
    if e.blocked: result.barriers.append({"layer":e.layer,"except_modes":e.get("except_modes",[])})
   "perception": result.perception[e.sense]=result.perception.get(e.sense,0.0)+e.value
   "behavior_weight": result.behavior_weights[e.behavior]=result.behavior_weights.get(e.behavior,0.0)+e.value
   "property_modifier": result.properties[e.property]=result.properties.get(e.property,0.0)+e.value
 for field in ["check_modifiers","perception","behavior_weights","properties"]:
  var cap: float=100.0 if field=="properties" else 10.0
  for key in result[field]: result[field][key]=clampf(result[field][key],-cap,cap)
 result.action_cost.multiplier_bps=clampf(result.action_cost.multiplier_bps,0,40000)
 result.damage.multiplier_bps=clampf(result.damage.multiplier_bps,0,40000)
 return result

static func adjusted_cost(base: int,aggregate_result: Dictionary) -> int:
 return maxi(0,int(ceil((base+aggregate_result.action_cost.flat)*aggregate_result.action_cost.multiplier_bps/10000.0)))

static func adjusted_damage(base: int,aggregate_result: Dictionary) -> int:
 return maxi(0,int((base+aggregate_result.damage.flat)*aggregate_result.damage.multiplier_bps/10000.0))

static func check_delta(aggregate_result: Dictionary) -> float:
 var total:=0.0
 for n in aggregate_result.check_modifiers.values(): total+=n
 return clampf(total,-10,10)

## Shared traversal predicate for host pathfinding and reachable overlay.
static func can_enter(actor_result: Dictionary,tile_result: Dictionary,cell: Dictionary,mode: String = "walk") -> bool:
 if mode not in ["walk","flight","swim","climb","burrow"]: return false
 if actor_result.movement.get(mode,mode=="walk")==false or tile_result.movement.get(mode,true)==false: return false
 if mode!="walk" and not actor_result.movement.get(mode,false): return false
 if cell.get("all_blocked",false) or _blocked(tile_result,"all",mode): return false
 if mode=="flight":
  if cell.get("air_blocked",false) or _blocked(tile_result,"air",mode) or cell.get("no_flight",false): return false
  if cell.has("ceiling_clearance") and cell.ceiling_clearance<cell.get("required_clearance",1): return false
  if cell.has("current_load") and cell.has("load_limit") and cell.current_load>cell.load_limit: return false
  return true
 # Swimming/climbing/burrowing require authored terrain eligibility, never magic wall bypass.
 if mode!="walk" and not mode in cell.get("allowed_modes",[]): return false
 return (not cell.get("ground_blocked",false) or (mode!="walk" and mode in cell.get("allowed_modes",[]))) and not _blocked(tile_result,"ground",mode)

## Resolves one host-owned event on a detached candidate. Caller commits it with its action.
## before excludes freshly applied statuses; event sequence is the host monotonic state clock.
func advance_event(before: Dictionary,store: Dictionary,event: Dictionary,owners: Dictionary) -> Dictionary:
 var checked:=validate(before)
 if not checked.ok: return checked
 checked=validate(store)
 if not checked.ok: return checked
 if not C.exact_fields(event,["trigger","owner_kind","owner_id","sequence","event_id","context"]) or not event.trigger is String or not event.trigger in Catalog.TRIGGERS or event.trigger=="query" or not event.owner_kind is String or not event.owner_kind in Catalog.SCOPES or not text(event.owner_id) or not C.integer(event.sequence) or event.sequence<1 or not text(event.event_id) or not Catalog.valid_context(event.context) or not C.safe(owners) or not C.safe(event): return C.fail("STATUS_EVENT","Malformed authoritative event")
 var key:=owner_key(event.owner_kind,event.owner_id)
 if not owners.has(key) or not owners[key] is Dictionary: return C.fail("STATUS_OWNER",key)
 var watermark: String=key+":"+event.trigger
 var previous: Dictionary=store.last_events.get(watermark,{})
 var prior: int=int(previous.get("sequence",0))
 if event.sequence<prior: return C.fail("STATUS_STALE_EVENT",watermark)
 if event.sequence==prior:
  if event.event_id!=previous.event_id or C.digest(event)!=previous.event_hash: return C.fail("STATUS_EVENT_CONFLICT","Same sequence has a different event identity or payload")
  return {"ok":true,"already_applied":true,"store":store.duplicate(true),"owners":owners.duplicate(true),"effects":[]}
 if not previous.is_empty() and event.event_id==previous.event_id: return C.fail("STATUS_EVENT_ID_REUSED","A newer sequence must not reuse the previous event identity")
 var eligible: Array=[]
 for instance_id in before.instances:
  if store.instances.has(instance_id) and before.instances[instance_id].generation==store.instances[instance_id].generation: eligible.append(instance_id)
 var evaluated:=evaluate(store,event.owner_kind,event.owner_id,event.context,event.trigger,eligible)
 if not evaluated.ok: return evaluated
 var copy: Dictionary=store.duplicate(true)
 var bodies: Dictionary=owners.duplicate(true)
 var changes: Array=[]
 for e in evaluated.effects:
  if e.op!="resource_delta": continue
  var pool: Variant=bodies[key].get(e.resource)
  if not C.exact_fields(pool,["current","max"]) or not C.integer(pool.current) or not C.integer(pool.max) or pool.current<0 or pool.current>pool.max or pool.max>1000000000: return C.fail("STATUS_RESOURCE",key+":"+e.resource)
  var amount: float=e.value
  if e.basis=="max_bps": amount=float(pool.max)*e.value/10000.0
  elif e.basis=="current_bps": amount=float(pool.current)*e.value/10000.0
  var delta: int=clampi(int(amount),-int(pool.current),int(pool.max)-int(pool.current))
  pool.current+=delta
  changes.append({"instance_id":e.instance_id,"resource":e.resource,"delta":delta})
 for instance_id in eligible:
  var s: Dictionary=copy.instances[instance_id]
  if s.owner_kind!=event.owner_kind or s.owner_id!=event.owner_id: continue
  var removed_by_event:=false
  var removal_context: Dictionary=C.normalized(event.context); removal_context["owner_kind"]=s.owner_kind
  for rule in entries[s.definition_id].get("removal_triggers",[]):
   if rule.trigger==event.trigger and conditions_match(rule.conditions,removal_context,store,s.owner_kind,s.owner_id):
    removed_by_event=true; break
  if removed_by_event:
   copy.instances.erase(instance_id); changes.append({"instance_id":instance_id,"removed":true}); continue
  var clock: String=entries[s.definition_id].duration.clock
  if not entries[s.definition_id].duration.get("persistent",false) and ((clock=="owner_action" and event.trigger=="owner_action_end") or (clock=="world_step" and event.trigger=="world_step")):
   s.remaining-=1
   if s.remaining==0: copy.instances.erase(instance_id)
 copy.last_events[watermark]={"sequence":event.sequence,"event_id":event.event_id,"event_hash":C.digest(event)}; copy.revision+=1
 checked=validate(copy)
 if not checked.ok: return checked
 return {"ok":true,"already_applied":false,"store":copy,"owners":bodies,"effects":changes}

## The entire JSON response obeys budget_bytes. Never ship the whole catalog per turn.
func compact_context(store: Dictionary,kind: String,id: String,context: Dictionary = {},budget_bytes: int = 4096) -> Dictionary:
 var evaluated:=evaluate(store,kind,id,context)
 if not evaluated.ok: return evaluated
 if budget_bytes<256 or budget_bytes>16384: return C.fail("STATUS_BUDGET","Budget must be 256..16384 bytes")
 var response: Dictionary={"schema_version":"active_status_context/v1","readonly":true,"catalog_hash":catalog_hash,"owner":owner_key(kind,id),"active":[],"omitted":0,"truncated":false,"authority":"program_validated; behavior_weights_are_soft"}
 var ids: Array=store.instances.keys(); ids.sort()
 for instance_id in ids:
  var s: Dictionary=store.instances[instance_id]
  if s.owner_kind!=kind or s.owner_id!=id: continue
  var entry: Dictionary={"id":s.definition_id,"p":s.parameters,"n":s.remaining,"clock":entries[s.definition_id].duration.clock,"stacks":s.stacks,"name":entries[s.definition_id].name,"category":entries[s.definition_id].category,"persistent":entries[s.definition_id].duration.get("persistent",false),"rules":_compact_rules(entries[s.definition_id],s.parameters)}
  if not entries[s.definition_id].conditions.is_empty(): entry["conditions"]=entries[s.definition_id].conditions
  if entries[s.definition_id].has("removal_triggers"): entry["remove_on"]=entries[s.definition_id].removal_triggers
  var proposed: Dictionary=response.duplicate(true); proposed.active.append(entry)
  # Reserve metadata space for up to 256 omitted records.
  if C.bytes(proposed).to_utf8_buffer().size()+32<=budget_bytes: response.active.append(entry)
  else: response.omitted+=1; response.truncated=true
 response["ok"]=true
 if C.bytes(response).to_utf8_buffer().size()>budget_bytes: return C.fail("STATUS_BUDGET","Even metadata exceeds supplied budget")
 return response.duplicate(true)

func definition_context(ids: Array,max_bytes: int = 8192) -> Dictionary:
 if ids.size()>12 or max_bytes<256 or max_bytes>16384: return C.fail("STATUS_DEFINITION_BUDGET","Ask for at most 12 definitions")
 var out: Dictionary={"ok":true,"readonly":true,"definitions":[]}
 for id in ids:
  if not entries.has(id): return C.fail("STATUS_UNKNOWN",str(id))
  out.definitions.append(entries[id].duplicate(true))
 if C.bytes(out).to_utf8_buffer().size()>max_bytes: return C.fail("STATUS_DEFINITION_BUDGET","Requested definition batch exceeds budget")
 return out

static func _compact_rules(definition: Dictionary,params: Dictionary) -> Array:
 var result: Array=[]
 for m in definition.mechanics:
  var row: Dictionary=m.duplicate(true)
  for k in Catalog.NUMERIC.get(m.op,[]): row[k]=scalar(m[k],params)
  if row.conditions.is_empty(): row.erase("conditions")
  result.append(row)
 return result

static func _blocked(result: Dictionary,layer: String,mode: String) -> bool:
 if not result.has("barriers"): return result.passability.get(layer,false)
 for barrier in result.barriers:
  if barrier.layer==layer and (layer=="all" or not mode in barrier.except_modes): return true
 return false

## Caller establishes equipped-item/area membership and spatial contact. No global aura guessing.
func evaluate_scopes(store: Dictionary,scopes: Array,context: Dictionary = {}) -> Dictionary:
 if scopes.is_empty() or scopes.size()>16: return C.fail("STATUS_SCOPE_BUDGET","Query one to sixteen authoritative owner references")
 var effects: Array=[]
 var seen: Dictionary={}
 for scope in scopes:
  if not C.exact_fields(scope,["kind","id"]) or not scope.kind is String or not scope.id is String: return C.fail("STATUS_SCOPE","Typed owner references required")
  var key:=owner_key(scope.kind,scope.id)
  if seen.has(key): return C.fail("STATUS_SCOPE","Duplicate scope would double-count effects")
  seen[key]=true
  var result:=evaluate(store,scope.kind,scope.id,context)
  if not result.ok: return result
  effects.append_array(result.effects)
 return {"ok":true,"readonly":true,"effects":effects,"aggregate":aggregate(effects,context)}
