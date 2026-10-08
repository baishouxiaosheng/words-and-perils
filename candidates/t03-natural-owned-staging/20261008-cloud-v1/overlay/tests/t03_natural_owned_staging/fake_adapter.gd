extends "res://view/generated_natural_coast_basic/adapter.gd"
const ProbeIO = preload("res://tests/t03_natural_owned_staging/io_probe.gd")
var use_fake_backend := false
func _new_save_staging_nonce() -> PackedByteArray:
	return ProbeIO.nonce() if use_fake_backend else super._new_save_staging_nonce()
func _make_save_staging_directory(path: String) -> Error:
	return ProbeIO.make_directory(path) if use_fake_backend else super._make_save_staging_directory(path)
func _open_save_temporary(path: String) -> RefCounted:
	return ProbeIO.open(path,ProbeIO.WRITE) if use_fake_backend else super._open_save_temporary(path)
func _open_save_staging_readback(path: String) -> RefCounted:
	return ProbeIO.readback(path) if use_fake_backend else super._open_save_staging_readback(path)
func _save_staging_payload_exists(path: String) -> bool:
	return ProbeIO.files.has(path) if use_fake_backend else super._save_staging_payload_exists(path)
func _remove_save_staging_path(path: String) -> Error:
	return ProbeIO.remove_fixed(path) if use_fake_backend else super._remove_save_staging_path(path)
func _rename_save_temporary(temporary: String, destination: String) -> Error:
	return ProbeIO.rename_absolute(temporary,destination) if use_fake_backend else super._rename_save_temporary(temporary,destination)
