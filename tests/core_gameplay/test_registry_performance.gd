extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const Weighted = preload("res://view/playable_build/weighted_movement_resolver.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
class RegistrySpy extends RefCounted:
	var supports_calls := 0
	var save_calls := 0
	func supports_resolver(id: String) -> bool:
		supports_calls += 1
		return id == "coast_move_route_v3"
	func save_data() -> Dictionary:
		save_calls += 1
		return {"resolver_ids": ["coast_move_route_v3"]}
var failures: Array = []
var checks := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var adapter := Adapter.new(9, true)
	var real_engine: RefCounted = adapter.engine
	var spy := RegistrySpy.new(); adapter.engine = spy
	var started := Time.get_ticks_msec()
	var goal := ""
	for i in range(10000): goal = adapter.movement_goal([i % 100, 0])
	var formatter_ms := Time.get_ticks_msec() - started
	expect(spy.save_calls == 0, "movement formatting never serializes world/save/receipts")
	expect(spy.supports_calls == 10000 and goal == "【署名样例】按地形耗力行至（99，0）。", "cheap registry metadata preserves exact signed goal")
	expect(formatter_ms < 2000, "ten thousand goal formats remain bounded")
	adapter.engine = real_engine
	expect(real_engine.supports_resolver(Weighted.ID) and not real_engine.supports_resolver("unknown"), "trusted registry lookup exact membership")
	var state: Dictionary = adapter.state_copy(); var keys: Array = state.hexes.keys(); keys.sort()
	var last: Dictionary = state.hexes[keys.back()]
	var target: Array = [last.q, last.r]
	expect(adapter.begin_intent(adapter.movement_goal(target)).ok, "full real map worst-order authored goal begins")
	var before: String = C.bytes(adapter.engine.save_data())
	started = Time.get_ticks_msec()
	for i in range(10): expect(adapter.fixture_available(), "exact signed full-map fixture match " + str(i))
	var matching_ms := Time.get_ticks_msec() - started
	expect(C.bytes(adapter.engine.save_data()) == before, "metadata checks cannot mutate pending state or RNG")
	expect(matching_ms < 5000, "ten worst-order real-map lookups avoid repeated full save serialization")
	print("REGISTRY PERFORMANCE ", checks - failures.size(), "/", checks, " formatter_ms=", formatter_ms, " matching_ms=", matching_ms, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
