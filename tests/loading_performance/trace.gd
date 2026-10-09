extends RefCounted
static var rows: Array = []
static func record(label_: String, start: int, memory_before: int) -> void:
	var row := {"stage":label_,"start_us":start,"end_us":Time.get_ticks_usec(),"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"static_delta_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_before,"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))}
	rows.append(row)
	print("LOAD_STAGE ", JSON.stringify(row))
