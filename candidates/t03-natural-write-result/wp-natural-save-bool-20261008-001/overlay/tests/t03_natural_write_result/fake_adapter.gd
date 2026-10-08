extends "res://view/generated_natural_coast_basic/adapter.gd"
const ProbeIO = preload("res://tests/t03_natural_write_result/io_probe.gd")
var use_fake_backend := false
func _open_save_temporary(path: String) -> RefCounted:
	return ProbeIO.open(path,ProbeIO.WRITE) if use_fake_backend else super._open_save_temporary(path)
func _rename_save_temporary(temporary: String, destination: String) -> Error:
	return ProbeIO.rename_absolute(temporary,destination) if use_fake_backend else super._rename_save_temporary(temporary,destination)

