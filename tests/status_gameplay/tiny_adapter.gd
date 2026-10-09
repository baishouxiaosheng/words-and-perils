extends "res://view/playable_build/adapter.gd"
## Only world construction is substituted with tiny OFFLINE authored cells.
## Public adapter movement methods and its actual engine/registry are unchanged.
const Fixture=preload("res://tests/status_gameplay/fixture.gd")
func _make_engine(seed:Variant=null,_legacy:=false,_paths:=true,_effects:=true,_basic:=true,_release:=true,_weighted:=true,_scenes:=false,_composites:=true,_scalar_scenes:=true,_gates:=true,_effects_v2:=true,_creative:=true) -> RefCounted:
 return Fixture.engine(1 if seed==null else int(seed))
