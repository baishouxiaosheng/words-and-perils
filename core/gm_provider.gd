extends RefCounted
## Provider boundary. Implementations return canonical GM decisions; none of the
## client providers is permitted to infer item effects or resolve gameplay.

func provider_info() -> Dictionary:
	return {"id": "abstract", "label": "GM provider", "live": false}

func request_decision(_request: Dictionary) -> Dictionary:
	return {"ok": false, "errors": ["Configure a GM provider."]}
