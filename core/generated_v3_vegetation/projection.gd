extends RefCounted
## Frozen selection is projected once; live read-only pages contain summaries.
## Pagination is a bounded query helper, never a gameplay action or capability.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/generated_v3_vegetation/catalog.gd")
const Focus = preload("res://core/generated_v3_vegetation/focus.gd")
const ID := "source_vegetation_context/v1"
const MAX_BYTES := 2048
const PAGE_SIZE := 3
const RADIUS := 2
const FOCUS_FIELDS := ["schema_version", "world_id", "kind", "id", "hex", "scene_id", "catalog_version", "catalog_id", "entity_revision"]
static func pick(value: Dictionary, fields: Array) -> Dictionary: return Catalog.pick(value, fields)
static func _dictionary(value: Variant) -> Dictionary: return value if value is Dictionary else {}
static func public_descriptor(value: Dictionary) -> Dictionary:
	var result := pick(value, Catalog.DESCRIPTOR_FIELDS)
	if result.has("root_support"): result.root_support = pick(_dictionary(result.root_support), Catalog.ROOT_SUPPORT_FIELDS)
	return result
static func summary(value: Dictionary) -> Dictionary: return pick(value, ["id", "hex", "asset_id"])
static func frozen_focus(focus: Dictionary, _cell_fields: Array = []) -> Dictionary:
	if focus.is_empty(): return {}
	var result := pick(focus, FOCUS_FIELDS)
	var facts := _dictionary(focus.get("facts", {}))
	# Full immutable evidence remains in history. catalog_id in the header binds
	# omitted repeated source/placement/location/cell facts; no polygon is sent.
	result["facts"] = {"descriptor":public_descriptor(_dictionary(facts.get("descriptor", {}))), "selection_is_action":false}
	return C.normalized(result)
static func _distance(a: Array, b: Array) -> int:
	var q := int(a[0]) - int(b[0]); var r := int(a[1]) - int(b[1])
	return maxi(absi(q), maxi(absi(r), absi(q + r)))
static func _page(catalog: Dictionary, state: Dictionary, scope: Dictionary, cursor: Dictionary, limit: int) -> Dictionary:
	var binding := C.digest({"catalog_id":catalog.catalog_hash, "scope":scope})
	var after_id := ""
	if not cursor.is_empty():
		if not C.exact_fields(cursor, ["binding", "after_id"]) or cursor.binding != binding or not Catalog.valid_id(cursor.after_id): return C.fail("VEGETATION_CURSOR", "Vegetation cursor belongs to another catalog or scope.")
		after_id = cursor.after_id
	var ids: Array = []
	for id in catalog.entries:
		var row: Dictionary = catalog.entries[id]
		if id != scope.excluded_id and _distance(row.hex, scope.center) <= scope.radius and Catalog.scene_for(row, state) == scope.scene_id: ids.append(id)
	ids.sort()
	if not after_id.is_empty() and not after_id in ids: return C.fail("VEGETATION_CURSOR", "Vegetation cursor is not an exact member of this bounded scope.")
	var start: int = 0 if after_id.is_empty() else ids.find(after_id) + 1
	var entries: Array = []
	for index in range(start, mini(start + limit, ids.size())): entries.append(summary(catalog.entries[ids[index]]))
	var next: Variant = null
	if start + entries.size() < ids.size(): next = {"binding":binding, "after_id":entries[-1].id}
	return C.normalized({"ok":true, "schema_version":ID, "catalog_id":catalog.catalog_hash, "scope":scope, "catalog_total":catalog.entries.size(), "total":ids.size(), "returned":entries.size(), "omitted":ids.size() - entries.size(), "after_id":after_id, "next_cursor":next, "entries":entries})
static func nearby_page(state: Dictionary, scene_id: String, center: Array, radius: int = RADIUS, excluded_id: String = "", cursor: Dictionary = {}, limit: int = PAGE_SIZE) -> Dictionary:
	if not Catalog.validate_world(state).ok: return C.fail("VEGETATION_PAGE", "Vegetation pages require a valid source world and bounded read-only scope.")
	return _nearby_page_checked(state, state.generated_world.vegetation_entity_catalog, scene_id, center, radius, excluded_id, cursor, limit)
static func _nearby_page_checked(state: Dictionary, catalog: Dictionary, scene_id: String, center: Array, radius: int, excluded_id: String, cursor: Dictionary, limit: int) -> Dictionary:
	if not Catalog.valid_hex(center) or not state.scenes.has(scene_id) or radius < 0 or radius > 2 or limit < 1 or limit > PAGE_SIZE or not C.safe(cursor): return C.fail("VEGETATION_PAGE", "Vegetation pages require a valid source world and bounded read-only scope.")
	if not excluded_id.is_empty() and not catalog.entries.has(excluded_id): return C.fail("VEGETATION_PAGE", "The excluded selection does not belong to this catalog.")
	var scope := {"scene_id":scene_id, "center":C.normalized(center), "radius":radius, "excluded_id":excluded_id}
	var result := _page(catalog, state, scope, cursor, limit)
	if result.ok and C.bytes(result).to_utf8_buffer().size() > MAX_BYTES: return C.fail("VEGETATION_BUDGET", "Vegetation page exceeds its fixed public byte budget.")
	return result
static func context(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	if not Catalog.validate_world(state).ok: return {}
	return _context_checked(state, focus, state.generated_world.vegetation_entity_catalog)
static func _context_checked(state: Dictionary, focus: Dictionary, catalog: Dictionary) -> Dictionary:
	# A single synchronous operation has already validated this exact world.
	# Reuse that result for history and pages, preserving all their other gates.
	var actor: Variant = state.get("actors", {}).get("actor_player")
	if not actor is Dictionary or not actor.get("scene_id") is String or not Catalog.valid_hex(actor.get("hex")): return {}
	var selected := ""; var frozen: Dictionary = {}
	if focus.get("kind") == "vegetation":
		if not Focus._validate_historical_checked(focus, state, catalog).is_empty(): return {}
		selected = focus.id; frozen = frozen_focus(focus)
	# The byte ceiling covers BOTH pieces as inserted into a model request.
	# Smaller pages retain truthful total/omitted and a usable exact cursor.
	for limit in [3, 2, 1]:
		var page := _nearby_page_checked(state, catalog, actor.scene_id, actor.hex, RADIUS, selected, {}, limit)
		if not page.ok: return {}
		page.erase("ok")
		if C.bytes({"frozen_focus":frozen, "vegetation":page}).to_utf8_buffer().size() <= MAX_BYTES: return page
	return {}
static func resolve_context(reference: Dictionary, state: Dictionary) -> Dictionary:
	# Preferred complete selection refresh from a Source-owned immutable header
	# table. Exactly one full validation; no global cache or trust in a caller's
	# mutable dictionary identity. Returned focus/context bytes are unchanged.
	var checked := Catalog.validate_world(state)
	if not checked.ok: return checked
	var catalog: Dictionary = state.generated_world.vegetation_entity_catalog
	var resolved := Focus._resolve_checked(reference, state, catalog)
	if not resolved.ok: return resolved
	var page := _context_checked(state, resolved.focus, catalog)
	if page.is_empty(): return C.fail("VEGETATION_CONTEXT", "Vegetation selection has no valid bounded public context.")
	return {"ok":true, "focus":resolved.focus, "context":page}
