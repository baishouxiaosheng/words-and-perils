extends "res://view/runtime_ai/scoped_engine.gd"
## Test-only: retain the pre-budget public projection, including refused ones.
var captured_request: Dictionary = {}
func _budget(full: Dictionary, scoped: Dictionary, key: String) -> Dictionary:
	captured_request = scoped.duplicate(true)
	return super._budget(full, scoped, key)
