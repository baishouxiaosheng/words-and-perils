extends RefCounted
## Local metadata and wire mapping only. No network/model catalog, credentials or saves.
const BaseCodec = preload("res://core/ai_gm_http/openai_chat_codec.gd")
const IDS := ["custom", "deepseek", "bigmodel_cn", "zai_intl", "openrouter"]
const LABELS := ["自定义 · OpenAI兼容", "DeepSeek", "智谱 GLM · 国内", "Z.AI GLM · 国际", "OpenRouter · 中转"]
const ENDPOINTS := {
	"custom":"",
	"deepseek":"https://api.deepseek.com/chat/completions",
	"bigmodel_cn":"https://open.bigmodel.cn/api/paas/v4/chat/completions",
	"zai_intl":"https://api.z.ai/api/paas/v4/chat/completions",
	"openrouter":"https://openrouter.ai/api/v1/chat/completions"
}
const MODEL_CATALOG_CHECKED := "2026-10-06"
## Offline, explicitly maintained IDs. No account entitlement, price, performance
## or live-service guarantee; no model discovery, alias guessing or fallback.
const MODELS := {
	"custom":[],
	"deepseek":[{"label":"DeepSeek Flash","id":"deepseek-flash"},{"label":"DeepSeek V4 Pro","id":"deepseek-v4-pro"}],
	"bigmodel_cn":[{"label":"GLM 5.3","id":"glm-5.3"},{"label":"GLM 5.2","id":"glm-5.2"},{"label":"GLM 4.7 Flash","id":"glm-4.7-flash"},{"label":"GLM 4.5 Air","id":"glm-4.5-air"}],
	"zai_intl":[{"label":"GLM 5.3","id":"glm-5.3"},{"label":"GLM 5.2","id":"glm-5.2"},{"label":"GLM 4.7 Flash","id":"glm-4.7-flash"},{"label":"GLM 4.5 Air","id":"glm-4.5-air"}],
	"openrouter":[{"label":"Gemini 3.1 Flash Lite","id":"google/gemini-3.1-flash-lite"},{"label":"Gemini 3.8 Flash","id":"google/gemini-3.8-flash"},{"label":"GLM 5","id":"z-ai/glm-5"},{"label":"DeepSeek V4 Flash","id":"deepseek/deepseek-v4-flash"}]
}
static func models(preset: String) -> Array: return MODELS.get(preset,[]).duplicate(true)
static func token_parameter(preset: String) -> String:
	return "max_tokens" if preset in ["deepseek","bigmodel_cn","zai_intl"] else "max_completion_tokens"
static func origin(endpoint: String) -> String:
	var regex := RegEx.new()
	regex.compile("^(https?)://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[^\\s]*)$")
	var matched := regex.search(endpoint.strip_edges())
	if matched==null: return ""
	var scheme: String=matched.get_string(1)
	var port: int=int(matched.get_string(3).substr(1)) if not matched.get_string(3).is_empty() else (443 if scheme=="https" else 80)
	return scheme+"://"+matched.get_string(2).to_lower()+":"+str(port)
static func endpoint_binding(endpoint: String) -> String:
	var value: String=endpoint.strip_edges()
	var host: String=origin(value)
	if host.is_empty(): return ""
	var path_start: int=value.find("/",value.find("://")+3)
	return host+value.substr(path_start)
static func infer(endpoint: String) -> String:
	for id in IDS:
		if id!="custom" and endpoint.strip_edges()==ENDPOINTS[id]: return id
	return "custom"
static func encode(request: Dictionary, config: Dictionary, provenance: Dictionary, trusted_instructions: String="") -> Dictionary:
	var body: Dictionary=BaseCodec.encode(request,config,provenance,trusted_instructions)
	return apply_wire(body,config)
static func apply_wire(body: Dictionary, config: Dictionary) -> Dictionary:
	if body.is_empty(): return {}
	# Legacy programmatic configure retains the exact old protocol until a user
	# explicitly saves the new form. New presets never imply extra capabilities.
	if not config.has("service_preset"): return body
	body.erase("store")
	body.erase("response_format")
	if bool(config.get("json_object_mode",false)): body.response_format={"type":"json_object"}
	body.erase("max_completion_tokens")
	body[String(config.get("token_parameter","max_completion_tokens"))]=int(config.get("max_completion_tokens",2048))
	# Existing codec emits reasoning_effort only for a nonempty explicit value.
	# No thinking toggle, temperature, JSON Schema, fallback or retry is inferred.
	return body
