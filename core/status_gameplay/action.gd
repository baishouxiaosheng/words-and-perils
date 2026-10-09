extends RefCounted
## One registered ordinary action family; no text-to-state shortcut or independent combat phase.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const ID:="coast_status_source/v1"
func resolver_id() -> String:return ID
func action_schema() -> Dictionary:
 return {"schema_version":"status_source_action/v1","resolver_id":ID,"bindings":{"actor_id":"existing acting actor","target_actor_id":"existing same-scene target","source_id":"owned item with status_source, or actor status_actions land"},"components":["delivery","effect"],"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"disposition":"advisory_only","existing_status_policy":"Identical parameters may refresh. Different existing potency must be cleared first; it is never silently overwritten.","source_parameters":"Definition, duration, exact potency, scope and cost are fixed by the public trusted source profile; AI cannot supply patches or additional numeric effect fields.","required_fact_paths":["/actors/<actor_id>","/actors/<target_actor_id>","/items/<source_id> OR /actors/<actor_id>/status_actions/land"],"requires_assessment":true}
func attempt_key(_snapshot: Dictionary,assessment: Dictionary) -> String:return ID+":"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary,assessment: Dictionary) -> Dictionary:
 var b:Dictionary=assessment.bindings
 var source:Dictionary=_source(snapshot,b)
 var statuses:Array=[]
 for s in snapshot.status_foundation.instances.values():
  if s.owner_kind=="actor" and s.owner_id==b.target_actor_id and s.definition_id==source.profile.definition_id:statuses.append({"id":s.id,"parameters":s.parameters})
 statuses.sort_custom(func(a:Dictionary,c:Dictionary)->bool:return a.id<c.id)
 var actor:Dictionary=snapshot.actors[b.actor_id];var target:Dictionary=snapshot.actors[b.target_actor_id]
 return {"modifier":preload("res://core/ai_gm_rebuilt/generic_actions_v2.gd")._release_modifier(actor),"actor_hex":actor.hex,"target_hex":target.hex,"scene":actor.scene_id,"source":source.profile,"available":source.get("available",false),"can_pay":int(actor.stamina.current)>=int(source.profile.stamina),"target_alive":target.health.current>0,"status":statuses}
func retry_commit_policy(snapshot:Dictionary,assessment:Dictionary,outcomes:Dictionary) -> Dictionary:
 if not false in outcomes.values():return {"retain":false}
 return {"retain":true,"fingerprint":attempt_fingerprint(snapshot,assessment)}
func check_policy(snapshot:Dictionary,assessment:Dictionary) -> Dictionary:
 var plan:Dictionary=freeze(snapshot,assessment)
 if not plan.ok:return plan
 var source:Dictionary=_source(snapshot,assessment.bindings)
 return {"ok":true,"policies":{"delivery":source.profile.check_policy,"effect":source.profile.check_policy}}
func freeze(snapshot:Dictionary,assessment:Dictionary) -> Dictionary:
 if not Content.active(snapshot):return C.fail("STATUS_RULESET","This action requires the explicitly enabled new ruleset")
 var b:Variant=assessment.get("bindings")
 if not C.exact_fields(b,["actor_id","target_actor_id","source_id"]):return C.fail("STATUS_BINDINGS","Stable actor, target and source IDs required")
 for value in b.values():
  if not value is String or value.is_empty():return C.fail("STATUS_BINDINGS","Bindings must be strings")
 if not snapshot.actors.has(b.actor_id) or not snapshot.actors.has(b.target_actor_id):return C.fail("STATUS_ACTOR","Unknown authoritative actor")
 var actor:Dictionary=snapshot.actors[b.actor_id];var target:Dictionary=snapshot.actors[b.target_actor_id]
 if actor.health.current<=0 or target.health.current<=0 or actor.scene_id!=target.scene_id:return C.fail("STATUS_TARGET","Living actors in the same scene required")
 if not _has_ref(assessment,"/actors/"+_path_id(b.actor_id)) or not _has_ref(assessment,"/actors/"+_path_id(b.target_actor_id)):return C.fail("STATUS_EVIDENCE","Every acting/target actor requires frozen public fact evidence")
 var source:Dictionary=_source(snapshot,b)
 if not source.get("ok",false):return source
 var p:Dictionary=source.profile
 if not source.available:return C.fail("STATUS_SOURCE_UNAVAILABLE","Source ownership, quantity or capability unavailable")
 if not _has_ref(assessment,source.fact_path):return C.fail("STATUS_EVIDENCE","Source capability requires a cited frozen public fact")
 var dq:int=int(actor.hex[0])-int(target.hex[0]);var dr:int=int(actor.hex[1])-int(target.hex[1])
 if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))>1 or (p.target_scope=="self" and actor.id!=target.id):return C.fail("STATUS_RANGE","Authored source range/scope does not allow this target")
 if actor.stamina.current<int(p.stamina):return C.fail("STATUS_RESOURCE","Insufficient stamina for the trusted source cost")
 if not assessment.get("components") is Array or assessment.components.size()!=2:return C.fail("STATUS_COMPONENTS","Delivery and effect components required")
 var seen:Dictionary={}
 for component in assessment.components:
  if not component.id in ["delivery","effect"] or seen.has(component.id):return C.fail("STATUS_COMPONENTS","Unknown or repeated component")
  seen[component.id]=true
  if not C.exact_fields(component.parameters,["A","D","P"]):return C.fail("STATUS_PARAMETERS","No arbitrary potency, duration or state data accepted")
  for name in ["A","D","P"]:
   if not C.integer(component.parameters[name]):return C.fail("STATUS_PARAMETERS","Integer uncertainty parameters required")
  if component.parameters.A<0 or component.parameters.A>4 or component.parameters.D<0 or component.parameters.D>4 or component.parameters.P< -2 or component.parameters.P>2:return C.fail("STATUS_PARAMETERS","Uncertainty parameters outside release rule bounds")
 var effects:Array=[]
 if p.operation=="apply":
  for active_status in snapshot.status_foundation.instances.values():
   if active_status.owner_kind=="actor" and active_status.owner_id==target.id and active_status.definition_id==p.definition_id and C.bytes(active_status.parameters)!=C.bytes(p.parameters):return C.fail("STATUS_DIFFERENT_POTENCY","目标已有不同强度的同类状态；先有效解除，不能用刷新悄悄改写药效。")
  var checked:Dictionary=Foundation.runtime().apply_status(snapshot.status_foundation,p.definition_id,"actor",target.id,b.source_id,p.parameters)
  if not checked.ok:return checked
  effects.append({"type":"status_v2_apply","definition_id":p.definition_id,"owner_kind":"actor","owner_id":target.id,"source_id":b.source_id,"parameters":p.parameters.duplicate(true)})
 else:
  for s in snapshot.status_foundation.instances.values():
   if s.owner_kind=="actor" and s.owner_id==target.id and s.definition_id==p.definition_id:effects.append({"type":"status_v2_remove","instance_id":s.id})
  if effects.is_empty():return C.fail("STATUS_ABSENT","No matching real status exists to remove")
  effects.sort_custom(func(a:Dictionary,c:Dictionary)->bool:return a.instance_id<c.instance_id)
  if p.definition_id=="flight" and not preload("res://core/status_gameplay/movement.gd").can_land(snapshot,target,target.hex):return C.fail("STATUS_LANDING","这里尚无登记落脚面；冒险落地、抓攀与坠落救援尚未接入，本次降落未执行。")
 var costs:Array=[]
 if p.stamina>0:costs.append({"type":"actor_pool_delta","actor_id":actor.id,"pool":"stamina","delta":-int(p.stamina)})
 if p.units>0:costs.append({"type":"item_quantity_delta","item_id":b.source_id,"delta":-int(p.units)})
 if snapshot.has("combat_turn") and actor.id=="actor_player" and p.operation=="apply" and p.definition_id=="poison" and target.faction in actor.get("combat_profile",{}).get("hostile_factions",[]):
  costs.append(preload("res://core/ai_gm_rebuilt/basic_effects.gd").turn_patch(snapshot,"enemy",target.id,int(snapshot.combat_turn.round)+1))
 var success:Array=costs.duplicate(true);success.append_array(effects)
 return {"ok":true,"resolver_id":ID,"branches":[{"id":"status_source_applied","requires":{"delivery":true,"effect":true},"patches":success},{"id":"status_source_not_applied","requires":{"delivery":false},"patches":costs},{"id":"status_source_resisted","requires":{"delivery":true,"effect":false},"patches":costs}]}
static func _source(snapshot:Dictionary,b:Dictionary) -> Dictionary:
 var actor:Dictionary=snapshot.actors[b.actor_id]
 if b.source_id=="land":
  var p:Variant=actor.get("status_actions",{}).get("land")
  if not Content.validate_profile(p):return C.fail("STATUS_SOURCE","No authored landing ability")
  return {"ok":true,"profile":p.duplicate(true),"available":true,"fact_path":"/actors/"+_path_id(b.actor_id)+"/status_actions/land"}
 if not snapshot.items.has(b.source_id):return C.fail("STATUS_SOURCE","Unknown item source")
 var item:Dictionary=snapshot.items[b.source_id]
 if not Content.validate_profile(item.get("status_source")):return C.fail("STATUS_SOURCE","Item has no trusted status source profile")
 return {"ok":true,"profile":item.status_source.duplicate(true),"available":item.get("owner_actor_id","")==actor.id and item.id in actor.inventory and int(item.quantity)>=int(item.status_source.units),"fact_path":"/items/"+_path_id(b.source_id)}
static func _has_ref(assessment:Dictionary,path:String) -> bool:
 for ref in assessment.get("fact_refs",[]):
  if ref.get("path")!=path:continue
  for component in assessment.get("components",[]):
   if not ref.id in component.fact_ref_ids:return false
  return true
 return false

static func _path_id(id:String) -> String:return id.replace("~","~0").replace("/","~1")
