extends "res://tests/runtime_ai_budget/baseline_scoped_engine.gd"
## Test-only: baseline stays byte-exact; capture does not transmit or admit it.
var captured_request: Dictionary = {}
func _budget(full: Dictionary, scoped: Dictionary, key: String) -> Dictionary:
	captured_request = scoped.duplicate(true)
	return super._budget(full, scoped, key)
