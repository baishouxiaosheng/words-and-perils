extends "res://view/playable_build/rule_release_v1.gd"
const PROFILE_RULE="generated_v3_actor_actions_release/v2"
func rule_id()->String:return PROFILE_RULE
func rule_schema()->Dictionary:
	var result:Dictionary=super.rule_schema();result.schema_version=PROFILE_RULE
	result["formula_origin"]="coast_release/v1";result["action_scope"]="source-registered ordinary actions for actual acting actor"
	return result
func allows_fixture_assessment(_snapshot:Dictionary,_reply:Dictionary,_goal:String,_focus:Dictionary)->bool:return false
