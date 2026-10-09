extends RefCounted
## Read-only presentation of committed status state. Never changes the world,
## emits patches, runs an event, or treats an actor's prose as status evidence.
const SourceProfiles=preload("res://core/status_gameplay/source_profiles.gd")
const Runtime = preload("res://core/status_foundation/runtime.gd")
const C = preload("res://core/status_foundation/canonical.gd")
const UNAVAILABLE := "状态信息暂不可用"
const LEGACY_NAMES := {"poison": "中毒", "flight": "飞行", "drunk": "醉酒"}
static var _runtime: RefCounted

static func _get_runtime() -> RefCounted:
	if _runtime == null:
		_runtime = Runtime.new()
	return _runtime

## Display adapter only: pass this to PlayerDetails.status_lines/caption.
## Deliberately does not copy the actor or its private/source/provider fields.
static func adapt_actor(world: Dictionary, actor: Dictionary) -> Dictionary:
	return {"status_details": public_details(world, actor)}

## Safe public payload for ModelView. Call with its committed/frozen snapshot,
## never the live world when projecting historical facts.
static func public_details(world: Dictionary, actor: Dictionary) -> Dictionary:
	if not world.has("status_foundation"):
		return C.normalized(_legacy_details(actor))
	var actor_id: Variant = actor.get("id")
	var actors: Variant = world.get("actors")
	if not actor_id is String or not actors is Dictionary or not actors.has(actor_id):
		return _unavailable()
	var body: Variant = actors[actor_id]
	if not body is Dictionary or not body.get("id") is String or body.get("id") != actor_id:
		return _unavailable()
	var rt: RefCounted = _get_runtime()
	if not rt.ready().get("ok", false):
		return _unavailable()
	var checked: Dictionary = rt.validate(world.status_foundation)
	if not checked.get("ok", false):
		# Never echo validator diagnostics: they may contain source or instance IDs.
		return _unavailable()
	var rows: Array = []
	for instance in world.status_foundation.instances.values():
		if instance.owner_kind != "actor" or instance.owner_id != actor_id:
			continue
		if not SourceProfiles.public_instance(world,instance):continue
		var definition: Dictionary = rt.entries[instance.definition_id]
		rows.append(_foundation_row(definition, instance, body))
	_sort_rows(rows)
	return C.normalized({"available": true, "rows": rows})

static func public_rows(world: Dictionary, actor: Dictionary) -> Array:
	return public_details(world, actor).rows.duplicate(true)

## Formats either a detached status_details payload or a legacy actor.
static func status_lines(actor: Dictionary) -> Array[String]:
	var details: Dictionary = _display_details(actor)
	var lines: Array[String] = []
	if not details.available:
		lines.append(UNAVAILABLE)
		return lines
	for row in details.rows:
		var pieces: Array[String] = [row.name, row.duration.text]
		for parameter in row.parameters:
			pieces.append(parameter.text)
		if row.stacks > 1:
			pieces.append("叠加%d层" % row.stacks)
		for effect in row.effects:
			pieces.append(effect)
		if not row.removal.is_empty():
			pieces.append("解除：" + "；".join(row.removal))
		lines.append(" · ".join(pieces))
	return lines

## Focus-only short lines. Consumes the same detached/frozen public packet;
## inventory/HUD wording and all authoritative numeric/projection fields stay exact.
static func focus_status_lines(actor: Dictionary) -> Array[String]:
	var details: Dictionary = _display_details(actor)
	var lines: Array[String] = []
	if not details.available:
		lines.append(UNAVAILABLE)
		return lines
	for row in details.rows:
		if not lines.is_empty():
			lines.append("")
		lines.append("%s · %s" % [row.name, row.duration.text])
		var calculations: Array[String] = []
		var has_damage: bool = row.has("damage") and row.damage is Dictionary and C.exact_fields(row.damage, ["before_health_cap", "at_current_health"]) and C.integer(row.damage.at_current_health) and row.damage.at_current_health >= 0
		for effect in row.effects:
			if has_damage and effect.begins_with("按当前生命单独计算：最多损失"):
				continue
			for sentence in effect.split("；", false):
				if sentence == "自身行动结束时结算":
					lines.append("触发：自身行动结束时")
				elif sentence == "两项伤害各自取整，不超过当时剩余生命":
					calculations.append("计算说明：" + sentence)
				else:
					lines.append(sentence)
		if has_damage:
			# Read the frozen typed result; do not recalculate from live actor HP,
			# narrative strings, hidden fields, or a later world snapshot.
			lines.append("当前损失上限：%d生命" % int(row.damage.at_current_health))
		for removal in row.removal:
			var wording: String = "使用有效的解毒手段" if removal == "提前解除需有效解毒结果确认" else removal
			lines.append("解除：" + wording)
		if row.stacks > 1:
			lines.append("叠加%d层" % row.stacks)
		for parameter in row.parameters:
			lines.append("计算：" + parameter.text)
		lines.append_array(calculations)
	return lines

static func status_caption(actor: Dictionary) -> String:
	var details: Dictionary = _display_details(actor)
	if not details.available:
		return UNAVAILABLE
	var names: Array[String] = []
	for row in details.rows:
		var unit:String="次行动" if row.duration.clock=="owner_action" else ("步" if row.duration.clock=="world_step" else "回合")
		var short_time:String="持续" if row.duration.persistent else str(row.duration.remaining)+unit
		names.append("%s %s" % [row.name, short_time])
	return " · ".join(names)

static func has_statuses(actor: Dictionary) -> bool:
	var details: Dictionary = _display_details(actor)
	# An unreadable state must not be presented as "没有持续状态".
	return not details.available or not details.rows.is_empty()

static func _unavailable() -> Dictionary:
	return {"available": false, "rows": []}

static func _duration(clock: String, remaining: int, persistent: bool) -> Dictionary:
	if persistent:
		# The stored sentinel ticks are not a countdown and are not made public.
		return {"clock": clock, "persistent": true, "text": "持续生效，不自动到期"}
	var unit := "次自身行动" if clock == "owner_action" else "个世界时间步"
	if clock == "legacy_turn":
		unit = "回合"
	return {"clock": clock, "remaining": remaining, "persistent": false, "text": "剩余%d%s" % [remaining, unit]}

static func _parameter(label: String, value: Variant, suffix := "") -> Dictionary:
	return {"label": label, "value": value, "text": "%s %s%s" % [label, _number(value), suffix]}

static func _number(value: Variant) -> String:
	return str(int(value)) if float(value) == floor(float(value)) else str(value)

static func _foundation_row(definition: Dictionary, instance: Dictionary, actor: Dictionary) -> Dictionary:
	var persistent: bool = definition.duration.get("persistent", false)
	var row: Dictionary = {
		"name": definition.name,
		"duration": _duration(definition.duration.clock, int(instance.remaining), persistent),
		"parameters": [], "stacks": int(instance.stacks), "effects": [], "removal": []
	}
	# Only the authored, numeric parameters have public display labels. No arbitrary
	# keys, description, removal prose, provenance, or source names are copied.
	if instance.parameters.has("intensity"):
		row.parameters.append(_parameter("强度", instance.parameters.intensity))
	if instance.definition_id == "poison":
		row.parameters.append(_parameter("固定伤害", instance.parameters.flat_damage))
		row.parameters.append(_parameter("最大生命伤害比例", float(instance.parameters.max_health_bps) / 100.0, "%"))
		row.effects.append("自身行动结束时结算；两项伤害各自取整，不超过当时剩余生命")
		var health: Variant = actor.get("health")
		if _valid_pool(health):
			# Runtime truncates each negative component toward zero, independently,
			# then caps it to the current pool. This is a current-value explanation,
			# not a prediction of the future tick or a second resource settlement.
			var damage: int = int(instance.parameters.flat_damage) + int(float(health.max) * float(instance.parameters.max_health_bps) / 10000.0)
			var current_damage: int = mini(damage, int(health.current))
			row["damage"] = {"before_health_cap": damage, "at_current_health": current_damage}
			row.effects.append("按当前生命单独计算：最多损失%d生命" % current_damage)
	elif instance.definition_id == "flight":
		row.effects.append("飞行状态已生效；每条路线仍须核验空中阻挡、禁飞、净空与载重")
		row.effects.append("地面阻挡可绕过；跨水与到期落脚仍须通过路线评估")
	if not persistent:
		row.removal.append("计时结束")
	match str(instance.definition_id):
		"poison": row.removal.append("提前解除需有效解毒结果确认")
		"flight": row.removal.append("提前结束需安全降落或有效来源解除确认")
		"asleep": row.removal.append("有效受伤或成功唤醒")
		"bleeding": row.removal.append("有效止血结果确认")
		_: row.removal.append("其他解除条件须由有效行动确认")
	return row

static func _valid_pool(pool: Variant) -> bool:
	return pool is Dictionary and C.integer(pool.get("current")) and C.integer(pool.get("max")) and pool.current >= 0 and pool.current <= pool.max and pool.max <= 1000000000

static func _legacy_details(actor: Dictionary) -> Dictionary:
	var statuses: Variant = actor.get("statuses", {})
	if not statuses is Dictionary:
		return _unavailable()
	var rows: Array = []
	for status in statuses.values():
		if not status is Dictionary or not status.get("kind") is String or not LEGACY_NAMES.has(status.kind):
			return _unavailable()
		if not C.integer(status.get("remaining_turns")) or status.remaining_turns < 1 or status.remaining_turns > 10000 or not C.integer(status.get("magnitude")) or status.magnitude < 0 or status.magnitude > 10000:
			return _unavailable()
		var row: Dictionary = {
			"name": LEGACY_NAMES[status.kind],
			"duration": _duration("legacy_turn", int(status.remaining_turns), false),
			"parameters": [], "stacks": 1, "effects": [], "removal": ["计时结束或有效解除行动"]
		}
		if status.kind == "poison":
			row.parameters.append(_parameter("每回合伤害", status.magnitude))
			row.effects.append("实际扣血不超过当时剩余生命")
		elif status.kind == "flight":
			row.effects.append("可越过地面阻挡，跨水仍须评估")
		rows.append(row)
	_sort_rows(rows)
	return {"available": true, "rows": rows}

static func _sort_rows(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)

## Strict bounded format for detached/historical public packets, not an authority writer.
static func valid_public_details(details:Variant) -> bool:
	if not C.exact_fields(details,["available","rows"]) or not details.available is bool or not details.rows is Array or details.rows.size()>64:return false
	if not details.available:return details.rows.is_empty()
	for row in details.rows:
		if not row is Dictionary:return false
		var fields:Array=["name","duration","parameters","stacks","effects","removal"]
		if row.has("damage"):fields.append("damage")
		if not C.exact_fields(row,fields) or not _public_text(row.name,128) or not C.integer(row.stacks) or row.stacks<1 or row.stacks>10000 or not row.duration is Dictionary or not row.parameters is Array or row.parameters.size()>16:return false
		var duration:Dictionary=row.duration
		if not duration.get("persistent") is bool:return false
		var duration_fields:Array=["clock","persistent","text"]
		if not duration.persistent:duration_fields.append("remaining")
		if not C.exact_fields(duration,duration_fields) or not duration.clock is String or not duration.clock in ["owner_action","world_step","legacy_turn"] or not _public_text(duration.text,512):return false
		if not duration.persistent and (not C.integer(duration.remaining) or duration.remaining<1 or duration.remaining>10000):return false
		for parameter in row.parameters:
			if not C.exact_fields(parameter,["label","value","text"]) or not _public_text(parameter.label,128) or not (parameter.value is int or parameter.value is float) or not C.safe(parameter.value) or not _public_text(parameter.text,512):return false
		for key in ["effects","removal"]:
			if not row[key] is Array or row[key].size()>32:return false
			for line in row[key]:
				if not _public_text(line,512):return false
		if row.has("damage"):
			if not C.exact_fields(row.damage,["before_health_cap","at_current_health"]) or not C.integer(row.damage.before_health_cap) or not C.integer(row.damage.at_current_health) or row.damage.before_health_cap<0 or row.damage.at_current_health<0 or row.damage.at_current_health>row.damage.before_health_cap:return false
	return true

static func _public_text(value:Variant,limit:int) -> bool:return value is String and not value.is_empty() and value.length()<=limit

static func _display_details(actor: Dictionary) -> Dictionary:
	if not actor.has("status_details"):return _legacy_details(actor)
	var details:Variant=actor.status_details
	return C.normalized(details) if valid_public_details(details) else _unavailable()
