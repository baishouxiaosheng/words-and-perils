extends RefCounted
## UI-independent exact mode custody. Merely looking away never commits/cancels a turn.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var coast: RefCounted
var generated: RefCounted
var active: RefCounted
var epoch := 0
func _init(coast_: RefCounted) -> void:coast=coast_;active=coast_
func enter(candidate: RefCounted) -> Dictionary:
	if active!=null and active.phase()!="idle":return C.fail("ACTION_IN_PROGRESS","Finish or legally cancel the existing action before changing worlds.")
	if candidate==null or not candidate.ready().ok:return C.fail("GENERATED_NOT_READY","Generated candidate was not admitted.")
	generated=candidate;active=candidate;epoch+=1
	return {"ok":true,"epoch":epoch}
func return_coast() -> Dictionary:
	if active==coast:return {"ok":true,"unchanged":true}
	if active.phase()!="idle":return C.fail("ACTION_IN_PROGRESS","A generated pending result must remain in its original world.")
	active=coast;epoch+=1
	return {"ok":true,"epoch":epoch}
func import_at(reply: Dictionary,expected_epoch: int,expected_action: String) -> Dictionary:
	if expected_epoch!=epoch or active.active_action!=expected_action:return C.fail("STALE_MODE_REPLY","Response belongs to a different world or action.")
	return active.import_reply(reply)
