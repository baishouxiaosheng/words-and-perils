extends RefCounted
## Original bounded data schema. Catalog is authored trusted content, never model code.
const C = preload("res://core/status_foundation/canonical.gd")
const SCHEMA := "status_catalog/v1"
const SCOPES := ["actor", "item", "tile", "area"]
const TRIGGERS := ["query", "owner_action_end", "world_step", "on_enter", "on_hit", "on_use"]
const FACTS := ["check", "action", "terrain", "damage_type", "movement_mode", "target_material", "light", "weather", "owner_kind", "is_player", "heat", "moisture", "incoming_damage", "ceiling_clearance", "required_clearance", "air_blocked", "no_flight", "source_active", "target_size", "current_load", "load_limit", "physical_contact", "extinguishable_by_water"]
const TEXT_FACTS := ["check","action","terrain","damage_type","movement_mode","target_material","light","weather","owner_kind"]
const BOOL_FACTS := ["is_player","air_blocked","no_flight","source_active","physical_contact","extinguishable_by_water"]
const NUMBER_FACTS := ["heat","moisture","incoming_damage","ceiling_clearance","required_clearance","target_size","current_load","load_limit"]
const OPS := {
 "resource_delta":{"resource":["health","stamina","durability"],"basis":["flat","max_bps","current_bps"]},
 "check_modifier":{"check":["any","attack","defense","balance","stealth","perception","social","mental","strength","craft","magic","survival","ranged","melee","navigation","endurance","healing","concentration","hearing","sight","smell"]},
 "action_cost":{"action":["any","move","attack","cast","interact","speak","use_item","rest","craft","observe"]},
 "movement":{"mode":["flight","swim","climb","burrow","walk"]},
 "passability":{"layer":["ground","air","all"]},
 "perception":{"sense":["sight","hearing","smell","magic"]},
 "behavior_weight":{"behavior":["approach","avoid","cooperate","attack","rest","investigate","flee","protect"]},
 "property_modifier":{"property":["friction","flammability","conductivity","visibility","noise","hardness","buoyancy","temperature","value","weight","grip","range","protection"]},
 "damage_modifier":{"damage_type":["any","physical","fire","cold","lightning","poison","acid","psychic","radiant","necrotic","sonic"]},
 "capability":{"capability":["deliberate_action","speech","vision_targeting","manual_action","ground_contact","concentration","item_use","hearing_targeting"]}
}
const NUMERIC := {"resource_delta":["value"],"check_modifier":["value"],"action_cost":["flat","multiplier_bps"],"perception":["value"],"behavior_weight":["value"],"property_modifier":["value"],"damage_modifier":["flat","multiplier_bps"]}

static func load_default() -> Dictionary:
 var path := "res://data/catalog.json"
 if not FileAccess.file_exists(path): return C.fail("CATALOG_MISSING",path)
 var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
 return compile(parsed)

static func compile(raw: Variant) -> Dictionary:
 if not C.safe(raw): return C.fail("CATALOG_SCHEMA","Catalog must be finite JSON-compatible data")
 raw=C.normalized(raw)
 if not C.exact_fields(raw,["schema_version","definitions"]) or not raw.schema_version is String or raw.schema_version != SCHEMA or not raw.definitions is Array or raw.definitions.is_empty() or raw.definitions.size()>512 or not C.safe(raw): return C.fail("CATALOG_SCHEMA","Invalid catalog envelope")
 var entries: Dictionary = {}
 for d in raw.definitions:
  var result := validate_definition(d)
  if not result.ok: return result
  if entries.has(d.id): return C.fail("CATALOG_DUPLICATE",d.id)
  entries[d.id] = d.duplicate(true)
 for d in entries.values():
  for other in d.conflicts:
   if not other is String or not entries.has(other) or other==d.id: return C.fail("CATALOG_CONFLICT",d.id+":"+str(other))
  for condition in d.conditions:
   if condition.has("status") and not entries.has(condition.status): return C.fail("CATALOG_CONDITION",d.id)
  for removal in d.get("removal_triggers",[]):
   for condition in removal.conditions:
    if condition.has("status") and not entries.has(condition.status): return C.fail("CATALOG_CONDITION",d.id)
  for m in d.mechanics:
   for condition in m.conditions:
    if condition.has("status") and not entries.has(condition.status): return C.fail("CATALOG_CONDITION",d.id)
 return {"ok":true,"entries":C.normalized(entries),"catalog_hash":C.digest(raw),"schema_version":SCHEMA}

static func validate_definition(d: Variant) -> Dictionary:
 var fields := ["id","name","category","description","scopes","parameters","duration","stacking","conflicts","conditions","mechanics","baseline","removal"]
 if d is Dictionary and d.has("removal_triggers"): fields.append("removal_triggers")
 if not C.exact_fields(d,fields): return C.fail("DEFINITION_FIELDS","Definition fields must match schema")
 for f in ["id","name","category","description","removal"]:
  if not d[f] is String or d[f].is_empty(): return C.fail("DEFINITION_TEXT",f)
 if d.id.length()>64 or d.id.to_snake_case()!=d.id or not d.id.is_valid_identifier(): return C.fail("DEFINITION_ID",d.id)
 if not d.scopes is Array or d.scopes.is_empty() or d.scopes.size()>4: return C.fail("DEFINITION_SCOPE",d.id)
 for scope in d.scopes:
  if not scope in SCOPES or d.scopes.count(scope)!=1: return C.fail("DEFINITION_SCOPE",d.id)
 if not d.parameters is Dictionary or d.parameters.is_empty() or d.parameters.size()>12: return C.fail("DEFINITION_PARAMETERS",d.id)
 for p in d.parameters:
  var bound: Variant = d.parameters[p]
  if not p is String or not p.is_valid_identifier() or not C.exact_fields(bound,["min","max","default"]): return C.fail("PARAMETER_SCHEMA",d.id)
  for f in ["min","max","default"]:
   if not number(bound[f]) or absf(bound[f])>1000000: return C.fail("PARAMETER_RANGE",d.id)
  if bound.min>bound.default or bound.default>bound.max: return C.fail("PARAMETER_RANGE",d.id)
 if not (C.exact_fields(d.duration,["clock","ticks"]) or C.exact_fields(d.duration,["clock","ticks","persistent"])) or (d.duration.has("persistent") and not d.duration.persistent is bool) or not d.duration.clock is String or not d.duration.clock in ["owner_action","world_step"] or not C.integer(d.duration.ticks) or d.duration.ticks<1 or d.duration.ticks>10000: return C.fail("DURATION",d.id)
 if not C.exact_fields(d.stacking,["mode","max_stacks"]) or not d.stacking.mode is String or not d.stacking.mode in ["refresh","intensity","replace","independent"] or not C.integer(d.stacking.max_stacks) or d.stacking.max_stacks<1 or d.stacking.max_stacks>10: return C.fail("STACKING",d.id)
 if d.stacking.mode=="intensity" and not d.parameters.has("intensity"): return C.fail("STACKING_INTENSITY",d.id)
 if not d.conflicts is Array or not valid_conditions(d.conditions): return C.fail("CONDITIONS",d.id)
 if not d.mechanics is Array or d.mechanics.is_empty() or d.mechanics.size()>12: return C.fail("MECHANICS",d.id)
 for m in d.mechanics:
  if not valid_mechanic(m,d): return C.fail("MECHANIC_SCHEMA",d.id+":"+str(m))
 if d.has("removal_triggers"):
  if not d.removal_triggers is Array or d.removal_triggers.size()>8: return C.fail("REMOVAL_TRIGGERS",d.id)
  for r in d.removal_triggers:
   if not C.exact_fields(r,["trigger","conditions"]) or not r.trigger is String or not r.trigger in TRIGGERS or r.trigger=="query" or not valid_conditions(r.conditions): return C.fail("REMOVAL_TRIGGERS",d.id)
 if not C.exact_fields(d.baseline,["context","trigger"]) or not valid_context(d.baseline.context) or not d.baseline.trigger is String or not d.baseline.trigger in TRIGGERS: return C.fail("BASELINE",d.id)
 return {"ok":true}

static func number(x: Variant) -> bool:
 return (x is int or x is float) and is_finite(float(x))

static func valid_conditions(conditions: Variant) -> bool:
 if not conditions is Array or conditions.size()>12: return false
 for condition in conditions:
  if not condition is Dictionary: return false
  var selector := "status" if condition.has("status") else "fact"
  if not C.exact_fields(condition,[selector,"op","value"]) or not condition.op is String: return false
  if selector=="fact" and (not condition.fact is String or not condition.fact in FACTS): return false
  if selector=="status" and (not condition.status is String or not condition.op in ["gte","lte"] or not number(condition.value)): return false
  if not condition.op is String or not condition.op in ["eq","ne","gte","lte","in"]: return false
  if condition.op in ["gte","lte"] and not number(condition.value): return false
  if condition.op=="in" and (not condition.value is Array or condition.value.size()>20): return false
  if condition.value is Dictionary or (condition.value is Array and condition.op!="in"): return false
  if selector=="fact":
   var values: Array=condition.value if condition.op=="in" else [condition.value]
   for value in values:
    if not valid_fact_value(condition.fact,value): return false
 return true

static func scalar_valid(value: Variant, parameters: Dictionary) -> bool:
 if number(value): return absf(value)<=1000000
 if not C.exact_fields(value,["param","scale"]) or not value.param is String or not parameters.has(value.param) or not number(value.scale) or absf(value.scale)>1000000: return false
 return maxf(absf(parameters[value.param].min*value.scale),absf(parameters[value.param].max*value.scale))<=1000000

static func valid_mechanic(m: Variant,d: Dictionary) -> bool:
 if not m is Dictionary or not m.get("op") is String or not OPS.has(m.get("op")) or not m.get("trigger") is String or not m.get("trigger") in TRIGGERS or not valid_conditions(m.get("conditions")): return false
 var fields := ["op","trigger","conditions"]
 for key in OPS[m.op]:
  fields.append(key)
  if not m.get(key) is String or not m.get(key) in OPS[m.op][key]: return false
 for key in NUMERIC.get(m.op,[]):
  fields.append(key)
  if not scalar_valid(m.get(key),d.parameters): return false
 if m.op in ["movement","capability"]:
  fields.append("allow")
  if not m.get("allow") is bool: return false
 if m.op=="passability":
  fields.append("blocked")
  if not m.get("blocked") is bool or not ("tile" in d.scopes or "area" in d.scopes): return false
  if m.has("except_modes"):
   fields.append("except_modes")
   if not m.except_modes is Array or m.except_modes.size()>4 or m.layer=="all": return false
   for mode in m.except_modes:
    if not mode in ["walk","flight","swim","climb","burrow"]: return false
 if not C.exact_fields(m,fields): return false
 return (m.trigger!="query") if m.op=="resource_delta" else m.trigger=="query"

static func valid_fact_value(fact: String,value: Variant) -> bool:
 if fact in TEXT_FACTS: return value is String or value is StringName
 if fact in BOOL_FACTS: return value is bool
 if fact in NUMBER_FACTS: return number(value) and absf(float(value))<=1000000000
 return false

static func valid_context(context: Variant) -> bool:
 if not context is Dictionary or not C.safe(context): return false
 for key in context:
  if not (key is String or key is StringName) or not valid_fact_value(String(key),context[key]): return false
 return true
