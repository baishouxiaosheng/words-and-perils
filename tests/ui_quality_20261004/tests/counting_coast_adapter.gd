extends "res://view/playable_build/adapter.gd"
## Test instrumentation only. Production rule/default RNG are inherited unchanged.
var copy_counts: Dictionary = {}
func reset_copy_counts() -> void:
	copy_counts = {"state_copy_calls": 0, "action_copy_calls": 0, "state_hex_entries": 0, "action_hex_entries": 0}
func state_copy() -> Dictionary:
	var result: Dictionary = super.state_copy()
	copy_counts.state_copy_calls = int(copy_counts.get("state_copy_calls", 0)) + 1
	copy_counts.state_hex_entries = int(copy_counts.get("state_hex_entries", 0)) + result.get("hexes", {}).size()
	return result
func action_copy() -> Dictionary:
	var result: Dictionary = super.action_copy()
	copy_counts.action_copy_calls = int(copy_counts.get("action_copy_calls", 0)) + 1
	copy_counts.action_hex_entries = int(copy_counts.get("action_hex_entries", 0)) + result.get("snapshot", {}).get("hexes", {}).size()
	return result
