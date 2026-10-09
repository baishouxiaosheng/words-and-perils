extends RefCounted
## Read an already-issued limited receipt; never upgrades renderer or cover status.
const PATH:="res://artifacts/natural_coast_ecology_v02_20261002/final_acceptance.json"
const SHA:="f2fb2936c94e18196e71a3ce22850b7841c6efad9f7e81d4b960c548e3760073"
static func load_receipt(manifest:Dictionary)->Dictionary:
	if FileAccess.get_sha256(PATH)!=SHA:return {"verified":false,"reason":"receipt hash absent or changed"}
	var p:=JSON.new()
	if p.parse(FileAccess.get_file_as_string(PATH))!=OK or not p.data is Dictionary:return {"verified":false,"reason":"receipt parse"}
	var r:Dictionary=p.data
	if str(r.get("candidate",{}).get("sha256",""))!=str(manifest.get("source_identity",{}).get("ecology_pending",{}).get("sha256","")):return {"verified":false,"reason":"candidate binding mismatch"}
	return {"verified":true,"sha256":SHA,"status":r.status,"scope":r.scope,"actual_renderer":r.actual_renderer,"actual_cover_density_and_recognition":r.actual_cover_density_and_recognition,"actual_river":r.actual_river,"complete_game_or_terrain_art_goal":r.complete_game_or_terrain_art_goal}
