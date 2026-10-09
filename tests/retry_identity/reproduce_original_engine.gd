extends "res://tests/retry_identity/reproduce_legacy.gd"
## Exact pre-fix source snapshots pinned by SOURCE_SNAPSHOT_20261003.json hashes.
## This re-exports legacy fixtures with full float precision for cross-process replay.
const OriginalEngine = preload("res://tests/retry_identity/baseline_v1/engine.gd")
const OriginalActions = preload("res://tests/retry_identity/baseline_v1/generic_actions.gd")
func registry(version := 1) -> Dictionary:
	var r := super.registry(version)
	for kind in ["manipulate_environment", "apply_condition"]:
		var resolver := OriginalActions.new(kind); r[resolver.resolver_id()] = resolver
	return r
func make(version := 1, initial: Dictionary = {}, seed_ := 1) -> RefCounted:
	var r := registry(version)
	return OriginalEngine.new(base if initial.is_empty() else initial, TestRule.new(r), r, {"npc_secret_allowlist": [], "public_flag_ids": ["coast_observed", "keeper_trust", "lamp_restored"]}, seed_)
