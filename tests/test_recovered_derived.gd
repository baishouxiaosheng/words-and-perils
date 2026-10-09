extends SceneTree
const Terrain := preload("res://view/recovered_terrain_loader.gd")
const Water := preload("res://view/recovered_terrain_water_loader.gd")
var checks := 0
var failures := []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAILED " + label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := "res://artifacts/hex_lake_ports_rebuilt_20261002/"
	var mesh := Terrain.load_file(directory + "mesh_12_r24.json")
	check(mesh.ok, "new derived schema admitted")
	if not mesh.ok: printerr(mesh); quit(2); return
	var water := Water.load_file(directory + "drainage_12_r24.json", mesh.world)
	check(water.ok, "exact derived upstream water admitted")
	if not water.ok: printerr(water); quit(2); return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "mesh_12_r24.json"))
	var bad := raw.duplicate(true); bad.format = Terrain.FORMAT
	check(not Terrain.decode(bad).ok, "mixed geometry format/version refused")
	bad = raw.duplicate(true); bad.recovery_status = "REBUILT_NEW_DATA_NO_HISTORICAL_PASS"
	check(not Terrain.decode(bad).ok, "old status on derived geometry refused")
	bad = raw.duplicate(true); bad.lake_policy.main_cells["hex:999,999"] = "lake:0"
	check(not Terrain.decode(bad).ok, "policy hex outside exact geometry refused")
	bad = raw.duplicate(true); bad.rebuilt_lake_ports.config.minimum_stage_dry_fraction = NAN
	check(not Terrain.decode(bad).ok, "nonfinite declared threshold refused")
	var wet_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "drainage_12_r24.json"))
	bad = wet_raw.duplicate(true); bad.format = Water.FORMAT
	check(not Water.decode(bad, mesh.world).ok, "mixed water format/version refused")
	bad = wet_raw.duplicate(true); bad.per_hex[0].stage_dry_fraction = NAN
	check(not Water.decode(bad, mesh.world).ok, "nonfinite stored policy fraction refused")
	bad = wet_raw.duplicate(true); bad.upstream.mesh_sha256 = "0".repeat(64)
	check(not Water.decode(bad, mesh.world).ok, "derived byte binding mismatch refused")
	check(water.water.declared_policy_stats.main_hexes == mesh.world.declared_policy.main_cells.size(), "policy count read from actual embedded declaration")
	check(water.water.declared_policy_stats.failures == 0, "admitted stored fractions satisfy their actual declared thresholds")
	check(water.water.failed_land_80 == water.water.declared_policy_stats.raw_original_domain_failures, "raw original-domain diagnostics retained separately")
	var report := {"checks": checks, "failures": failures, "mesh_hash": mesh.world.semantic_hash, "water_hash": water.water.semantic_hash, "policy_stats": water.water.declared_policy_stats, "scope": "adapter admission and stored-fraction diagnostics; independent whole-world acceptance is separate"}
	var file := FileAccess.open("res://artifacts/recovered_terrain_viewer_20261002/derived_adapter_test_report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("RECOVERED_DERIVED_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
