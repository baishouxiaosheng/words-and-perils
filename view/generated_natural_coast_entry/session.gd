extends RefCounted
## v24 isolated overlay session, native acceptance pending.
## Reads host authority for custody, but never loads, replaces, commits or saves it.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const HostCustody = preload("res://view/generated_v3_river_entry/host_custody.gd")
const CoastAdapter = preload("res://view/generated_natural_coast_basic/adapter.gd")
const CoastSource = preload("res://view/generated_natural_coast_basic/source.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const ENTRY_ID := "natural_coast_basic_entry_r4/v1"
const HOST_STATUS_FIELDS := ["world_build_busy","generated_start_busy","end_turn_busy","runtime_busy","active_action"]
var coast: RefCounted
var _host: RefCounted
var _host_digest := ""
var _open := false
var _parked_coast_saves: Dictionary = {}
var recipe := "coastal_range"

static func descriptor() -> Dictionary:
	return {"id":ENTRY_ID,"label":"自然海岸 · 基础探索","default":false,"seed":726381,"radius":4,"recipes":["coastal_range","plateau_hinterland"],"notice":"独立基础探索，只含移动、观察、休息、行礼包放下与拾回；不改原旅程。没有村庄、NPC、战斗、植被、装备或实体河道。","network":"offline authored assessments only; no provider or credentials are shared"}
static func validate_status(status: Dictionary) -> Dictionary:
	if not C.exact_fields(status,HOST_STATUS_FIELDS):
		return C.fail("COAST_HOST_STATUS", "入口需要完整的主世界忙碌状态，未切换。")
	for field in ["world_build_busy","generated_start_busy","end_turn_busy","runtime_busy"]:
		if not status[field] is bool: return C.fail("COAST_HOST_STATUS", "入口状态类型无效，未切换。")
		if status[field]: return C.fail("COAST_HOST_BUSY", "请先完成当前加载、行动或接口请求，再打开实验。")
	if not status.active_action is String or not status.active_action.is_empty():
		return C.fail("COAST_HOST_PENDING", "当前行动仍在处理，未取消或替换原旅程。")
	return {"ok":true}

func enter(host: RefCounted, status: Dictionary, entry_id: String, chosen_recipe: String = "coastal_range") -> Dictionary:
	if entry_id != ENTRY_ID: return C.fail("COAST_ENTRY_CHOICE", "只有明确选择实验入口才能开启自然海岸探索。")
	if chosen_recipe not in ["coastal_range","plateau_hinterland"]: return C.fail("COAST_RECIPE","Only the two explicitly verified radius-4 recipes are admitted.")
	if _open: return C.fail("COAST_ENTRY_ALREADY_OPEN", "实验窗口已经打开；不会建立第二个世界。")
	var checked := validate_status(status)
	if not checked.ok: return checked
	var custody:Dictionary=HostCustody.capture(host)
	if not custody.ok:return custody
	if host.phase() != "idle": return C.fail("COAST_HOST_PENDING", "原旅程的行动尚未完成，未切换。")
	var snapshot: Dictionary = custody.snapshot
	var before := C.digest(snapshot)
	var candidate: RefCounted = CoastAdapter.new()
	var parked: Dictionary = _parked_coast_saves.get(chosen_recipe,{})
	if not parked.is_empty():
		checked = candidate.load_data(parked)
		if not checked.get("ok",false): return checked
		if C.bytes(candidate.save_data()) != C.bytes(parked):
			return C.fail("COAST_RESTORE_DRIFT", "实验进度不能精确重建，原旅程保持不变。")
	else:
		var generated: Dictionary = Generator.generate("726381",4,chosen_recipe)
		if not generated.get("ok",false): return generated
		checked = candidate.start_source(generated.source)
		if not checked.get("ok",false): return checked
	if candidate.source.data.recipe.id != chosen_recipe: return C.fail("COAST_RECIPE_CUSTODY","The parked save belongs to another explicit recipe.")
	checked = candidate.ready()
	if not checked.get("ok",false): return checked
	# Synchronous construction must not alter the retained host in any way.
	custody=HostCustody.capture(host)
	if not custody.ok:return custody
	if C.digest(custody.snapshot) != before or host.phase() != "idle":
		return C.fail("COAST_HOST_DRIFT", "原旅程在入口准备期间变化；没有回滚或覆盖任何状态。")
	recipe = chosen_recipe; _host = host; _host_digest = before; coast = candidate; _open = true
	return {"ok":true,"entry":descriptor(),"identity":coast.source.identity.duplicate(true),"host_unchanged":true}

func leave() -> Dictionary:
	if not _open or _host == null: return C.fail("COAST_ENTRY_NOT_OPEN", "实验当前未打开。")
	if coast == null or not coast.ready().get("ok",false): return C.fail("COAST_SESSION", "实验状态不可验证，未替换原旅程。")
	if coast.phase() != "idle": return C.fail("COAST_PENDING", "请先完成当前实验行动或明确取消，再返回；不会自动结算或取消。")
	var custody:Dictionary=HostCustody.capture(_host)
	if not custody.ok:return custody
	if C.digest(custody.snapshot) != _host_digest or _host.phase() != "idle":
		return C.fail("COAST_HOST_DRIFT", "原旅程在实验期间变化；没有回滚、迁移或覆盖，请检查。")
	var retained: Dictionary=coast.save_data()
	if not C.safe(retained) or C.bytes(retained).to_utf8_buffer().size()>CoastAdapter.MAX_SAVE_BYTES:
		return C.fail("COAST_PARKING_BUDGET", "实验进度不能安全保留，未丢弃或覆盖。")
	_parked_coast_saves[recipe] = retained.duplicate(true)
	var retained_hash := C.digest(_parked_coast_saves[recipe])
	# Retain only exact JSON custody. The controller frees the view; navigation,
	# meshes and the guest adapter must not remain as a third resident world.
	coast = null; _open = false; _host = null; _host_digest = ""
	return {"ok":true,"host_unchanged":true,"coast_save_retained":true,"coast_save_hash":retained_hash}

func is_open() -> bool: return _open
