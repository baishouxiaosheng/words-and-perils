extends "res://view/playable_build/rule_release_v1.gd"
const Examples=preload("res://view/generated_v3_equipment/assessments.gd")
const ENEMY_ID="generated_v3_village_equipment_release/v1"
func rule_id()->String:return ENEMY_ID
func rule_schema()->Dictionary:
	var result:Dictionary=super.rule_schema();result.schema_version=ENEMY_ID
	result["formula_origin"]="coast_release/v1";result["supported_scope"]="village exploration, bundle custody, registered conversation, one separately assessed melee encounter, one conserved downed-enemy blade pickup and owned staff/blade equipment"
	return result
func allows_fixture_assessment(snapshot:Dictionary,reply:Dictionary,goal:String,focus:Dictionary)->bool:return Examples.verify(snapshot,reply,goal,focus)
