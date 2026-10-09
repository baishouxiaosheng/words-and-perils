extends RefCounted
## Gate B support. Full source Coast only; never constructs a small-world fallback.
## Every gameplay change uses a trusted resolver through the ordinary transaction.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BudgetProbe = preload("res://tests/status_river_gate_b/request_budget_probe.gd")
static var budget_observations: Array = []
const Coast = preload("res://view/playable_build/adapter.gd")
const Content = preload("res://core/status_gameplay/content.gd")
const Action = preload("res://core/status_gameplay/action.gd")
const Foundation = preload("res://core/status_foundation/engine_bridge.gd")
const Save = preload("res://view/status_gameplay/save.gd")
const Details = preload("res://view/status_gameplay/details.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const Weighted = preload("res://view/playable_build/weighted_movement_resolver.gd")
const Movement = preload("res://core/status_gameplay/movement.gd")
const EXPECTED = "res://tests/status_river_gate_b/expected_default_world.json"
const SEED = 1
const PLAYER = "actor_player"
const SOURCE_PROFILES = {"item_poison_vial":"poison_vial", "item_feather_vial":"feather_vial", "item_status_antidote":"antidote"}

static func adapter() -> RefCounted:
	# Exact production adapter with explicitly labelled release-rule test mode.
	return Coast.new(SEED, true, true)

static func identity(state: Dictionary) -> Dictionary:
	var generated: Dictionary = state.get("generated_world", {})
	return {"world_id":state.get("world_id"), "hex_count":state.get("hexes", {}).size(), "scene_id":state.get("actors", {}).get(PLAYER, {}).get("scene_id"), "bundle_id":generated.get("bundle_id"), "source_mesh_sha256":generated.get("source_mesh_sha256"), "source_drainage_sha256":generated.get("source_drainage_sha256"), "catalog_sha256":generated.get("catalog_sha256")}

static func world_check(state: Dictionary) -> Dictionary:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	if not expected is Dictionary or expected.get("hex_count") != 1801:
		return C.fail("GATE_EXPECTATION", "Missing fixed full-world expectation")
	var actual := identity(state)
	if C.bytes(actual) != C.bytes(expected):
		return C.fail("GATE_SOURCE_IDENTITY", "Full source world differs: " + C.bytes(actual))
	if state.get("scenes", {}).get("scene_coast", {}).get("hex_ids", []).size() != 1801:
		return C.fail("GATE_SCENE_SIZE", "Actual coast scene must contain all 1801 source cells")
	if not Bundle.ready() or Bundle.bundle_id() != expected.bundle_id or Bundle.catalog_sha256() != expected.catalog_sha256:
		return C.fail("GATE_BUNDLE", "Loaded bundle differs from pinned source identity")
	return {"ok":true, "identity":actual}

static func source_check(state: Dictionary) -> bool:
	if not Content.active(state) or not Content.validate(state).ok:
		return false
	for id in SOURCE_PROFILES:
		var item: Dictionary = state.get("items", {}).get(id, {})
		if C.bytes(item.get("status_source")) != C.bytes(Content.profile(SOURCE_PROFILES[id])) or item.has("condition_source"):
			return false
	return C.bytes(state.actors[PLAYER].status_actions.land) == C.bytes(Content.profile("land"))

static func assessment(request: Dictionary, resolver_id: String, bindings: Dictionary, components: Array) -> Dictionary:
	if request.is_empty() or request.get("phase") != "assessment":
		return {}
	var paths: Array = ["/actors/" + str(bindings.actor_id)]
	if bindings.has("target_actor_id"):
		var target_path := "/actors/" + str(bindings.target_actor_id)
		if not target_path in paths:
			paths.append(target_path)
	if bindings.has("source_id"):
		paths.append("/actors/" + str(bindings.actor_id) + "/status_actions/land" if bindings.source_id == "land" else "/items/" + str(bindings.source_id))
	if bindings.has("target_hex"):
		var h: Array = bindings.target_hex
		var key := "%d,%d" % h
		var scene_id: String = request.context.facts.actors[bindings.actor_id].scene_id
		paths.append("/scene_hexes/" + scene_id + "/" + key if request.context.facts.get("scene_hexes", {}).has(scene_id) else "/hexes/" + key)
	var refs: Array = []
	var ids: Array = []
	for i in range(paths.size()):
		var fact: Dictionary = C.pointer(request.context.facts, paths[i])
		if not fact.ok:
			return {}
		var id := "fact_" + str(i)
		ids.append(id)
		refs.append({"id":id, "path":paths[i], "expected":fact.value})
	var parts: Array = []
	for id in components:
		parts.append({"id":id, "parameters":{"A":4,"D":0,"P":2}, "disposition":"certain", "fact_ref_ids":ids.duplicate()})
	return {"schema_version":"ai_gm_assessment/v1", "action_id":request.action_id, "state_version":request.state_version, "context_hash":request.context_hash, "narration":"离线作者测试评估，尚未执行；不代表真实模型判断。", "interpretation":"Gate B offline authored assessment citing the actual full Coast source facts; no live model call.", "resolver_id":resolver_id, "bindings":bindings.duplicate(true), "components":parts, "fact_refs":refs, "provenance":{"provider":"offline_gate_b_authored_assessment", "live":false, "kind":"model_reply"}}

static func source_bindings(id: String) -> Dictionary:
	return {"actor_id":PLAYER, "target_actor_id":PLAYER, "source_id":id}

static func begin(adapter_: RefCounted, resolver: String, bindings: Dictionary, components: Array) -> Dictionary:
	var begun: Dictionary = adapter_.begin_intent("【Gate B 离线作者测试】" + resolver + " " + C.bytes(bindings))
	if not begun.ok:
		return begun
	var reply := assessment(begun.request, resolver, bindings, components)
	if reply.is_empty():
		return C.fail("GATE_EVIDENCE", "Required actual source facts were not available")
	if resolver == Action.ID:
		var budget: Dictionary = inspect_request_budget(adapter_,reply)
		if not budget.ok:
			return C.fail("GATE_COMPLETE_REQUEST_BUDGET", C.bytes(budget))
	return {"ok":true, "reply":reply}

static func prepare_source(adapter_: RefCounted, source: String) -> Dictionary:
	var begun := begin(adapter_, Action.ID, source_bindings(source), ["delivery", "effect"])
	if not begun.ok:
		return begun
	return adapter_.import_reply(begun.reply)

static func commit_prepared(adapter_: RefCounted) -> Dictionary:
	var rolled: Dictionary = adapter_.roll_once()
	if not rolled.ok:
		return rolled
	var staged: Dictionary = adapter_.stage()
	if not staged.ok:
		return staged
	return adapter_.commit()

static func status(state: Dictionary, id: String) -> Dictionary:
	for row in state.get("status_foundation", {}).get("instances", {}).values():
		if row.owner_kind == "actor" and row.owner_id == PLAYER and row.definition_id == id:
			return row
	return {}

static func authored_poison_setup(adapter_: RefCounted) -> Dictionary:
	# ONLY a labelled initial condition for the independent antidote test. This is
	# not a claimed source-world fact or a gameplay application. No player pool,
	# inventory, location, RNG, receipt or action is edited. Application coverage
	# is independently obtained by the real poison-vial pipeline.
	var data: Dictionary = adapter_.engine.save_data()
	if data.state.turn != 0 or not data.pending.is_empty() or not data.receipts.is_empty() or not data.state.status_foundation.instances.is_empty():
		return C.fail("GATE_FIXTURE_SCOPE", "Authored poison may only seed a fresh isolated fixture")
	var added: Dictionary = Foundation.runtime().apply_status(data.state.status_foundation, "poison", "actor", PLAYER, "offline_gate_b_initial_poison_NOT_source_fact", Content.profile("poison_vial").parameters)
	if not added.ok:
		return added
	data.state.status_foundation = added.store
	return adapter_.engine.load_data(data)

static func player_reference(state: Dictionary) -> Dictionary:
	return {"world_id":state.world_id, "kind":"actor", "id":PLAYER, "hex":state.actors[PLAYER].hex.duplicate(), "scene_id":state.actors[PLAYER].scene_id}

static func tile_reference(state: Dictionary, target: Array) -> Dictionary:
	var cell: Dictionary = state.hexes.get("%d,%d" % target, {})
	if cell.is_empty():
		return {}
	return {"world_id":state.world_id, "kind":"tile", "id":cell.id, "hex":target.duplicate(), "scene_id":cell.scene_id}

static func first_neighbor_route(adapter_: RefCounted) -> Dictionary:
	# At most six source-adjacent candidates; no seed search or world rebuilding.
	var state: Dictionary = adapter_.state_copy()
	var origin: Array = state.actors[PLAYER].hex
	for delta in [[1,0], [0,1], [-1,1], [-1,0], [0,-1], [1,-1]]:
		var target: Array = [int(origin[0])+int(delta[0]), int(origin[1])+int(delta[1])]
		if not state.hexes.has("%d,%d" % target) or not Movement.can_land(state,state.actors[PLAYER],target):
			continue
		var route: Dictionary = adapter_.movement_preview(target)
		if route.get("ok", false) and route.get("route", []).size() >= 2:
			return {"ok":true, "target":target, "preview":route}
	return C.fail("GATE_ROUTE_PRECONDITION", "No source-adjacent affordable route; do not mutate terrain to force this test")

static func inspect_request_budget(adapter_: RefCounted, reply: Dictionary) -> Dictionary:
	var result: Dictionary = BudgetProbe.inspect(adapter_.engine,reply)
	budget_observations.append(result.duplicate(true))
	return result
