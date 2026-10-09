extends SceneTree
## Lightweight fixture. Run only in the parent's copied candidate and guarded
## native slot; this file does not launch/import the full game or its assets.
const Details = preload("res://view/status_gameplay/details.gd")
const Runtime = preload("res://core/status_foundation/runtime.gd")
const C = preload("res://core/status_foundation/canonical.gd")
var count := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	count += 1
	if not value:
		failures.append(label)
		printerr("FAIL " + label)

func actor(id := "actor_player") -> Dictionary:
	return {"id": id, "name": "旅人", "health": {"current": 83, "max": 120}, "stamina": {"current": 15, "max": 20}, "statuses": {}, "secrets": {"hidden": "PRIVATE_ACTOR_SECRET"}, "provider": {"api_key": "PRIVATE_PROVIDER"}}

func world_with(store: Dictionary, body: Dictionary) -> Dictionary:
	return {"status_foundation": store.duplicate(true), "actors": {body.id: body.duplicate(true)}}

func find_row(rows: Array, name_: String) -> Dictionary:
	for row in rows:
		if row.name == name_:
			return row
	return {}

func event(trigger: String, sequence: int) -> Dictionary:
	return {"trigger": trigger, "owner_kind": "actor", "owner_id": "actor_player", "sequence": sequence, "event_id": trigger + str(sequence), "context": {}}

func _initialize() -> void:
	var rt := Runtime.new()
	expect(rt.ready().get("ok", false), "real foundation catalog loads")
	if not rt.ready().get("ok", false):
		finish()
		return
	expect(rt.entries.size() == 168, "UI does not expand the 168-definition catalog")
	var body: Dictionary = actor()
	var empty_world: Dictionary = world_with(rt.empty(), body)
	expect(Details.public_details(empty_world, body).available, "empty opted-in store is readable")
	expect(Details.public_rows(empty_world, body).is_empty(), "empty opted-in store has no invented status")
	expect(not Details.has_statuses(Details.adapt_actor(empty_world, body)), "empty state caption remains empty")

	var legacy: Dictionary = body.duplicate(true)
	legacy.statuses = {
		"PRIVATE_LEGACY_POISON": {"id": "PRIVATE_LEGACY_POISON", "kind": "poison", "remaining_turns": 2, "magnitude": 4},
		"PRIVATE_LEGACY_FLIGHT": {"id": "PRIVATE_LEGACY_FLIGHT", "kind": "flight", "remaining_turns": 1, "magnitude": 1}
	}
	var legacy_lines := "\n".join(Details.status_lines(legacy))
	expect(legacy_lines.contains("中毒") and legacy_lines.contains("飞行"), "v1 poison and flight remain visible")
	expect(legacy_lines.contains("剩余2回合") and legacy_lines.contains("每回合伤害 4"), "v1 counter and magnitude are exact")
	expect(not legacy_lines.contains("自身行动"), "v1 clock is not silently relabeled owner_action")
	expect(not legacy_lines.contains("PRIVATE"), "legacy stable IDs and private actor fields never render")
	var legacy_adapter := Details.adapt_actor({}, legacy)
	expect(legacy_adapter.keys() == ["status_details"], "adapter is a minimal safe display packet")
	expect(not JSON.stringify(legacy_adapter).contains("PRIVATE"), "adapter excludes actor secrets and provider credentials")
	var opted_in_with_legacy := world_with(rt.empty(), legacy)
	expect(Details.public_rows(opted_in_with_legacy, legacy).is_empty(), "foundation is sole authority when opted in")

	var applied: Dictionary = rt.apply_status(rt.empty(), "poison", "actor", body.id, "PRIVATE_SOURCE_SECRET", {"flat_damage": 2.9, "max_health_bps": 1000, "intensity": 3})
	expect(applied.ok, "real runtime accepts bounded fractional flat poison")
	if not applied.ok:
		finish()
		return
	var store: Dictionary = applied.store
	var poison_world := world_with(store, body)
	var before_bytes := C.bytes(poison_world)
	var poison: Dictionary = find_row(Details.public_rows(poison_world, body), "中毒")
	expect(poison.duration.clock == "owner_action" and poison.duration.remaining == 3, "owner_action clock and remaining are public")
	expect(poison.duration.text == "剩余3次自身行动", "owner action display is explicit")
	expect(poison.damage.before_health_cap == 14 and poison.damage.at_current_health == 14, "poison components truncate separately: 2 plus 12")
	expect(poison.parameters[0].value == 3 and poison.parameters[1].value == 2.9 and poison.parameters[2].value == 10.0, "actual intensity, flat damage, and percent are preserved")
	expect("\n".join(Details.status_lines(Details.adapt_actor(poison_world, body))).contains("最多损失14生命"), "poison numerical explanation is displayed")
	expect(C.bytes(poison_world) == before_bytes, "read-only formatting cannot mutate committed world")
	var dishonest_actor: Dictionary = body.duplicate(true)
	dishonest_actor.health.max = 9999
	dishonest_actor.status_details = {"available": true, "rows": [{"name": "NARRATIVE_INVENTED_STATUS"}]}
	dishonest_actor.statuses = legacy.statuses.duplicate(true)
	expect(Details.public_details(poison_world, dishonest_actor) == Details.public_details(poison_world, body), "committed actor wins over preview health, v1 fields, and narrative projection")

	var low_health: Dictionary = body.duplicate(true)
	low_health.health.current = 2
	poison = find_row(Details.public_rows(world_with(store, low_health), low_health), "中毒")
	expect(poison.damage.at_current_health == 2, "current health caps poison explanation")
	low_health.health.current = 0
	expect(find_row(Details.public_rows(world_with(store, low_health), low_health), "中毒").damage.at_current_health == 0, "zero HP does not display negative health")
	var tiny: Dictionary = rt.apply_status(rt.empty(), "poison", "actor", body.id, "PRIVATE_TINY", {"flat_damage": 0, "max_health_bps": 1})
	expect(find_row(Details.public_rows(world_with(tiny.store, body), body), "中毒").damage.before_health_cap == 0, "small fractional percentage does not invent a minimum damage")

	var flight: Dictionary = rt.apply_status(store, "flight", "actor", body.id, "PRIVATE_FLIGHT_SOURCE", {"intensity": 2})
	var wet: Dictionary = rt.apply_status(flight.store, "wet", "actor", body.id, "PRIVATE_WATER", {"intensity": 4})
	var persistent: Dictionary = rt.apply_status(wet.store, "restrained", "actor", body.id, "PRIVATE_RESTRAINT")
	var full_world := world_with(persistent.store, body)
	var rows: Array = Details.public_rows(full_world, body)
	expect(rows.size() == 4, "all committed actor instances are represented once")
	var flight_row := find_row(rows, "飞行")
	expect(flight_row.parameters[0].value == 2 and flight_row.duration.remaining == 3, "flight intensity and duration are actual committed values")
	expect("；".join(flight_row.effects).contains("禁飞") and "；".join(flight_row.effects).contains("载重"), "flight display preserves route constraints")
	expect(not "；".join(flight_row.effects).contains("任意"), "flight never promises unrestricted movement")
	var wet_row := find_row(rows, "湿润")
	expect(wet_row.duration.clock == "world_step" and wet_row.duration.text == "剩余5个世界时间步", "world_step duration is not confused with owner actions")
	var restrained := find_row(rows, "束缚")
	expect(restrained.duration.persistent and not restrained.duration.has("remaining"), "persistent status omits sentinel countdown")
	expect(restrained.duration.text.contains("不自动到期") and not "；".join(restrained.removal).contains("计时结束"), "persistent status never advertises natural expiration")
	expect(not flight_row.removal.is_empty() and not find_row(rows, "中毒").removal.is_empty(), "visible poison and flight removal conditions are supplied")
	var serialized := JSON.stringify(Details.public_details(full_world, body))
	for forbidden in ["PRIVATE", "source_id", "definition_id", "instance_id", "schema_version", "catalog_hash", "provider", "status_"]:
		expect(not serialized.contains(forbidden), "public payload excludes " + forbidden)

	var adapted := Details.adapt_actor(full_world, body)
	adapted.status_details.rows[0].parameters[0].value = 999
	adapted.status_details.rows[0].duration.text = "changed only detached output"
	adapted.status_details.rows[0].removal.append("changed only detached array")
	expect(JSON.stringify(Details.public_details(full_world, body)) == serialized, "nested output edits cannot mutate cache or world")
	var detached: Array = Details.public_rows(full_world, body)
	detached[0].effects.append("private detached edit")
	expect(JSON.stringify(Details.public_details(full_world, body)) == serialized, "public_rows returns independently detached nested arrays")

	var owner_pools := {"actor:actor_player": body.duplicate(true)}
	var tick: Dictionary = rt.advance_event(persistent.store, persistent.store, event("owner_action_end", 1), owner_pools)
	expect(tick.ok, "real owner action event executes in fixture")
	var after_body: Dictionary = tick.owners["actor:actor_player"]
	var tick_rows := Details.public_rows(world_with(tick.store, after_body), after_body)
	expect(find_row(tick_rows, "中毒").duration.remaining == 2 and find_row(tick_rows, "飞行").duration.remaining == 2, "UI follows actual owner-action decrement")
	expect(find_row(tick_rows, "湿润").duration.remaining == 5, "owner action does not age world-step status")
	expect(find_row(tick_rows, "束缚").duration.persistent, "persistent display survives owner action")
	var step: Dictionary = rt.advance_event(tick.store, tick.store, event("world_step", 1), tick.owners)
	var step_body: Dictionary = step.owners["actor:actor_player"]
	var step_world := world_with(step.store, step_body)
	var step_rows := Details.public_rows(step_world, step_body)
	expect(find_row(step_rows, "湿润").duration.remaining == 4 and find_row(step_rows, "中毒").duration.remaining == 2, "UI follows explicit world step only for that clock")
	var reopened: Dictionary = JSON.parse_string(JSON.stringify(step_world))
	var reopened_details:Dictionary=Details.public_details(reopened,reopened.actors.actor_player)
	var live_details:Dictionary=Details.public_details(step_world,step_body)
	if reopened_details!=live_details:
		print("DETAIL_REOPENED ",JSON.stringify(reopened_details,"",true,true))
		print("DETAIL_LIVE ",JSON.stringify(live_details,"",true,true))
	expect(reopened_details==live_details,"JSON save/reopen produces identical public details")
	var removed: Dictionary = rt.remove_status(store, applied.instance_id)
	expect(Details.public_rows(world_with(removed.store, body), body).is_empty(), "real removal disappears without UI mutation")
	var expired: Dictionary = store
	var expiry_owners: Dictionary = owner_pools.duplicate(true)
	for sequence in range(1, 4):
		var advanced: Dictionary = rt.advance_event(expired, expired, event("owner_action_end", sequence), expiry_owners)
		expired = advanced.store
		expiry_owners = advanced.owners
	expect(Details.public_rows(world_with(expired, body), body).is_empty(), "natural expiry disappears from projection")

	var unknown_world: Dictionary = full_world.duplicate(true)
	unknown_world.status_foundation.instances.values()[0].definition_id = "PRIVATE_UNKNOWN_DEFINITION"
	var unavailable := Details.adapt_actor(unknown_world, body)
	expect(not unavailable.status_details.available and unavailable.status_details.rows.is_empty(), "unknown status fails closed")
	expect(Details.has_statuses(unavailable) and Details.status_caption(unavailable) == Details.UNAVAILABLE, "unreadable status does not masquerade as no status")
	expect(not "\n".join(Details.status_lines(unavailable)).contains("PRIVATE"), "unknown-ID validator diagnostics never render")
	var forged_source: Dictionary = full_world.duplicate(true)
	forged_source.status_foundation.instances.values()[0].source_id = {"secret": "PRIVATE_MALFORMED_SOURCE"}
	expect(not Details.public_details(forged_source, body).available, "malformed source fails closed without echo")
	var foreign: Dictionary = rt.apply_status(store, "poison", "actor", "actor_other", "PRIVATE_OTHER")
	expect(Details.public_rows(world_with(foreign.store, body), body).size() == 1, "other actors' states are not disclosed")
	var wrong_body: Dictionary = body.duplicate(true)
	wrong_body.id = "PRIVATE_UNKNOWN_ACTOR"
	expect(not Details.public_details(full_world, wrong_body).available, "unknown actor is not matched heuristically")
	var invalid_legacy: Dictionary = body.duplicate(true)
	invalid_legacy.statuses = {"PRIVATE_BAD": {"kind": "PRIVATE_UNKNOWN_KIND", "remaining_turns": 2, "magnitude": 1}}
	expect(Details.status_lines(invalid_legacy) == [Details.UNAVAILABLE], "unknown v1 kind has safe unavailable text")
	check_focus_formatter(poison_world, body, flight_row, legacy)
	finish()

func check_focus_formatter(poison_world: Dictionary, body: Dictionary, flight_row: Dictionary, legacy: Dictionary) -> void:
	var packet: Dictionary = Details.adapt_actor(poison_world, body)
	packet["health"] = {"current": 0, "max": 1}
	packet["provider"] = {"api_key": "PRIVATE_FOCUS_PROVIDER"}
	packet["secrets"] = {"source_id": "PRIVATE_FOCUS_SOURCE"}
	var packet_bytes: String = C.bytes(packet)
	var inventory_before: Array[String] = Details.status_lines(packet)
	var caption_before: String = Details.status_caption(packet)
	var frozen_damage: int = int(packet.status_details.rows[0].damage.at_current_health)
	var focus_lines: Array[String] = Details.focus_status_lines(packet)
	expect(C.bytes(packet) == packet_bytes, "focus formatter leaves full nested frozen packet byte-exact")
	expect(Details.status_lines(packet) == inventory_before and Details.status_caption(packet) == caption_before, "focus-only formatting preserves inventory and HUD output")
	expect(focus_lines[0] == "中毒 · 剩余3次自身行动", "focus begins with status name and actual remaining clock")
	expect(focus_lines.has("触发：自身行动结束时"), "poison trigger has its own short focus line")
	expect(focus_lines.has("当前损失上限：%d生命" % frozen_damage) and frozen_damage == 14, "focus damage reads the typed frozen result despite unrelated live-health fields")
	expect(focus_lines.has("解除：使用有效的解毒手段") and focus_lines.has("解除：计时结束"), "poison focus shows concise removal methods on separate lines")
	var first_math: int = focus_lines.find("计算：强度 3")
	expect(first_math > focus_lines.find("解除：使用有效的解毒手段") and focus_lines.find("当前损失上限：14生命") < first_math, "focus puts current effect and removal ahead of calculation details")
	expect(focus_lines.has("计算：固定伤害 2.9") and focus_lines.has("计算：最大生命伤害比例 10%") and focus_lines[-1].begins_with("计算说明："), "focus retains real fractional and percentage math at the end")
	expect(focus_lines.all(func(line: String) -> bool: return line.length() <= 48), "poison focus uses short readable lines instead of one mathematical paragraph")
	for hidden in ["PRIVATE", "api_key", "provider", "source_id", "schema_version"]:
		expect(not "\n".join(focus_lines).contains(hidden), "focus cannot inject actor private fields: " + hidden)
	var repeated: Array[String] = Details.focus_status_lines(packet)
	focus_lines[0] = "PRIVATE_DETACHED_LINE"
	focus_lines.append("PRIVATE_DETACHED_APPEND")
	expect(Details.focus_status_lines(packet) == repeated and C.bytes(packet) == packet_bytes, "editing returned focus array cannot alias packet or later calls")
	var extra_field: Dictionary = packet.duplicate(true)
	extra_field.status_details.rows[0]["source_id"] = "PRIVATE_ROW_SOURCE"
	var extra_before: String = C.bytes(extra_field)
	expect(not "\n".join(Details.focus_status_lines(extra_field)).contains("PRIVATE") and C.bytes(extra_field) == extra_before, "unknown private packet fields are never rendered or removed by focus formatter")
	var flight_packet := {"status_details": {"available": true, "rows": [flight_row.duplicate(true)]}}
	var flight_before: String = C.bytes(flight_packet)
	var flight_focus: Array[String] = Details.focus_status_lines(flight_packet)
	expect(flight_focus.has("飞行状态已生效") and flight_focus.has("地面阻挡可绕过") and flight_focus.has("跨水与到期落脚仍须通过路线评估"), "flight focus splits existing sentences without widening travel authority")
	expect(flight_focus[-1] == "计算：强度 2" and C.bytes(flight_packet) == flight_before, "flight parameter is last and frozen flight packet stays exact")
	var legacy_focus := "\n".join(Details.focus_status_lines(legacy))
	expect(legacy_focus.contains("剩余2回合") and legacy_focus.contains("每回合伤害 4") and not legacy_focus.contains("自身行动"), "legacy focus preserves original turn and magnitude rules")
	expect(Details.focus_status_lines({"status_details": {"available": false, "rows": []}}) == [Details.UNAVAILABLE], "unavailable packet remains unavailable in focus")

func finish() -> void:
	var report := {"suite": "status_details", "assertions": count, "failures": failures, "ok": failures.is_empty()}
	print(JSON.stringify(report))
	var output := FileAccess.open("res://artifacts/status_details_report.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t") + "\n")
	quit(0 if failures.is_empty() else 1)
