extends RefCounted
## Independent implementation. See docs/reference_adoption/README.md.
## Catalog entries describe admission to assessment, never automatic execution.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "action_capability_catalog/v1"
const MAX_TARGETS := 48

static func build(public_facts: Dictionary, resolver_ids: Array, schemas: Dictionary, actor_id: String, admission: Dictionary, selected_focus: Dictionary = {}) -> Dictionary:
	var entries: Array = []
	for id in resolver_ids:
		var schema: Dictionary = schemas.get(id, {})
		entries.append({"resolver_id": id, "available": bool(admission.get("ok", false)), "availability_scope": "may_request_assessment_only", "reason_code": "ASSESSMENT_REQUIRED" if admission.get("ok", false) else admission.get("code", "UNAVAILABLE"), "reasons": ["A supplied assessment must pass the trusted resolver before an action is legal."] if admission.get("ok", false) else admission.get("errors", []), "bindings": schema.get("bindings", {}), "components": schema.get("components", []), "required_fact_paths": schema.get("required_fact_paths", []), "schema_available": not schema.is_empty()})
	var actor: Dictionary = public_facts.get("actors", {}).get(actor_id, {})
	var targets: Array = []
	var total := 0
	for collection in ["actors", "items", "environment_entities", "passage_targets", "scene_transitions"]:
		var records: Dictionary = public_facts.get(collection, {})
		var ids: Array = records.keys(); ids.sort()
		for id in ids:
			var record: Dictionary = records[id]
			var scene: String = record.get("scene_id", record.get("source_scene_id", ""))
			if not scene.is_empty() and scene != actor.get("scene_id", ""): continue
			if collection == "items" and record.get("owner_actor_id", "") not in ["", actor_id]: continue
			total += 1
			if targets.size() >= MAX_TARGETS: continue
			targets.append({"kind": {"actors":"actor", "items":"item", "environment_entities":"environment_entity", "passage_targets":"passage_edge", "scene_transitions":"scene_transition"}[collection], "id": id, "fact_path": "/" + collection + "/" + String(id).replace("~", "~0").replace("/", "~1"), "scene_id": scene, "hex": record.get("hex", record.get("source_hex", []))})
	return C.normalized({"schema_version": SCHEMA, "readonly": true, "actor_id": actor_id, "state_version": public_facts.get("state_version", 0), "entries": entries, "target_refs": targets, "target_refs_truncated": total > targets.size(), "selected_target_ref": _selected(selected_focus), "target_policy": "Public same-scene references and owned items are candidates, not range/ownership/semantic permission. Selection never binds an action.", "exact_query": "query_capability(assessment) validates an existing awaiting-assessment action on an isolated copy, without a roll or commit."})

static func _selected(focus: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["kind", "id", "scene_id", "hex"]:
		if focus.has(key): result[key] = focus[key]
	return result
