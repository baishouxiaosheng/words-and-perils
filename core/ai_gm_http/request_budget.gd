extends RefCounted
## Application public-JSON budget, not a provider context/token limit.
## Legacy callers remain at 64 KiB; a larger budget needs explicit configuration.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const LEGACY_BYTES := 65536
const CITY_BYTES := 98304
const CEILING_BYTES := 131072
static func validate(value: Variant) -> Dictionary:
	if not C.integer(value) or value < 1 or value > CEILING_BYTES:
		return C.fail("INVALID_REQUEST_BUDGET", "公开内容上限须为1至131072之间的整数字节；不会自动调整。")
	return {"ok":true, "bytes":int(value)}
static func exceeded(used: int, limit: int) -> Dictionary:
	var result := C.fail("CONTEXT_BUDGET", "公开内容为%d字节，超过已选上限%d字节（%.1f KiB）。未发送、未裁剪；可取消意图，或在连接设置中明确调整上限后重试。较大请求可能增加费用。" % [used, limit, float(limit)/1024.0])
	result["used_bytes"] = used; result["budget_bytes"] = limit
	return result
