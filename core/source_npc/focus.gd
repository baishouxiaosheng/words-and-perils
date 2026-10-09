extends RefCounted
## Live selection freezes complete NPC evidence. History reads only that witness.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Catalog = preload("res://core/source_npc/catalog.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const PublicProjection = preload("res://core/source_npc/projection.gd")
const VERSION := "source-npc-focus/v1"
const REF_FIELDS := ["world_id","kind","id","hex","scene_id","catalog_version","catalog_id","location_revision","contact_revision"]
const FACT_FIELDS := ["scene_id","source_identity","catalog_identity","descriptor","actor","public_state","supporting_cell","location_witness","selection_is_action"]
const LOCATION_FIELDS := ["kind","scene_id","hex","location_revision","placement_witness"]
static func reference_for(focus: Dictionary) -> Dictionary: return PublicProjection.pick(focus,REF_FIELDS)
static func cell(state: Dictionary, scene_id: String, hex: Variant) -> Dictionary:
	if not Catalog.valid_hex(hex) or not state.get("scenes",{}).has(scene_id): return {}
	var found: Dictionary = Cells.cell(state,scene_id,hex)
	return found if found.get("scene_id") == scene_id and found.get("q") == hex[0] and found.get("r") == hex[1] else {}
static func make_reference(id: String, state: Dictionary) -> Dictionary:
	if not Catalog.valid_id(id) or not NPCState.validate_world(state).ok or not state.has("npc_state") or not state.generated_world.npc_catalog.entries.has(id): return {}
	var actor: Dictionary = state.actors[id]
	return C.normalized({"world_id":state.world_id,"kind":"actor","id":id,"hex":actor.hex,"scene_id":actor.scene_id,"catalog_version":VERSION,"catalog_id":state.generated_world.npc_catalog.catalog_hash,"location_revision":actor.location_revision,"contact_revision":state.npc_state.contacts[id].revision})
static func _location(descriptor_: Dictionary) -> Dictionary:
	return {"kind":"source_npc","scene_id":descriptor_.scene_id,"hex":descriptor_.hex.duplicate(),"location_revision":descriptor_.location_revision,"placement_witness":descriptor_.placement_witness.duplicate(true)}
static func resolve(reference: Dictionary, state: Dictionary) -> Dictionary:
	if not C.exact_fields(reference,REF_FIELDS) or not C.safe(reference) or not reference.id is String: return C.fail("NPC_FOCUS","人物目标需要完整身份、位置与接触版本。")
	var current: Dictionary = make_reference(reference.id,state)
	if current.is_empty() or C.bytes(reference) != C.bytes(current): return C.fail("NPC_FOCUS","人物位置、接触版本或目录已变化，请重新选择。")
	var catalog: Dictionary = state.generated_world.npc_catalog
	var descriptor_: Dictionary = catalog.entries[current.id]
	var focus: Dictionary = current.duplicate(true)
	focus.schema_version = 1
	focus.facts = {"scene_id":current.scene_id,"source_identity":catalog.source_identity.duplicate(true),"catalog_identity":Catalog.identity(state),"descriptor":descriptor_.duplicate(true),"actor":PublicProjection.public_actor(state.actors[current.id]),"public_state":state.npc_state.contacts[current.id].duplicate(true),"supporting_cell":cell(state,current.scene_id,current.hex).duplicate(true),"location_witness":_location(descriptor_),"selection_is_action":false}
	return {"ok":true,"focus":C.normalized(focus)}
static func validate_historical(value: Dictionary, state: Dictionary) -> Array:
	if not NPCState.validate_world(state).ok or not state.has("npc_state") or not C.exact_fields(value,REF_FIELDS + ["schema_version","facts"]) or not C.safe(value): return ["Historical NPC requires its exact catalog and frozen witness."]
	var catalog: Dictionary = state.generated_world.npc_catalog
	if value.schema_version != 1 or value.catalog_version != VERSION or value.catalog_id != catalog.catalog_hash or value.world_id != state.world_id or value.kind != "actor" or not value.id is String or not catalog.entries.has(value.id) or not C.integer(value.location_revision) or value.location_revision != 0 or not C.integer(value.contact_revision) or value.contact_revision < 0 or value.contact_revision > state.npc_state.contacts[value.id].revision: return ["Historical NPC identity or revisions are invalid."]
	var descriptor_: Dictionary = catalog.entries[value.id]
	if value.scene_id != descriptor_.scene_id or C.bytes(value.hex) != C.bytes(descriptor_.hex): return ["Historical NPC location differs from its immutable reservation."]
	var facts: Variant = value.facts
	if not C.exact_fields(facts,FACT_FIELDS) or facts.scene_id != value.scene_id or not facts.selection_is_action is bool or facts.selection_is_action: return ["Historical NPC facts are malformed or treated as action authority."]
	if C.bytes(facts.source_identity) != C.bytes(catalog.source_identity) or C.bytes(facts.catalog_identity) != C.bytes(Catalog.identity(state)) or C.bytes(facts.descriptor) != C.bytes(descriptor_): return ["Historical NPC source or immutable descriptor changed."]
	if not Catalog.actor_matches_descriptor(facts.actor,descriptor_) or not NPCState.valid_contact(facts.public_state,int(state.turn)) or facts.public_state.revision != value.contact_revision: return ["Historical NPC actor or frozen public contact state is invalid."]
	if not C.exact_fields(facts.location_witness,LOCATION_FIELDS) or C.bytes(facts.location_witness) != C.bytes(_location(descriptor_)) or C.bytes(facts.supporting_cell) != C.bytes(cell(state,value.scene_id,value.hex)): return ["Historical NPC supporting cell or frozen location changed."]
	return []
