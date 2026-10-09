extends RefCounted
## Transport seam only. This version has no network, authentication or sockets.
## A client can submit intent text + attention; never a transform or effect patch.

func submit_intent(_command: Dictionary) -> Dictionary:
	return {"ok": false, "code": "TRANSPORT_NOT_CONFIGURED"}
