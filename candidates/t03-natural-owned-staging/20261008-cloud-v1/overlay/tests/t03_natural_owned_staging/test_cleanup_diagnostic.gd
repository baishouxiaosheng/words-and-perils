extends "res://tests/t03_natural_owned_staging/test_owned_staging.gd"
## Dedicated expected-error observation. Original strict guard must mark diagnostics.
## Never report this as a zero-ERROR successful gate or suppress production push_error.
func _initialize() -> void:
	diagnostic_only = true
	_run.call_deferred()
