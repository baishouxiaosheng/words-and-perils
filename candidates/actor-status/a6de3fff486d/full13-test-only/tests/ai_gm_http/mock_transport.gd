extends Node
## No HTTPRequest node, HTTPClient, sockets, credentials, or network calls.
## Replies are driven by the test, including deliberately late/duplicate replies.
signal completed(request_id: int, http_status: int, body: String, error_code: String)
var sent: Array[Dictionary] = []
var cancellations: Array[int] = []
var send_error: Error = OK
var cancellation_response := ""
var synchronous_response := ""

func info() -> Dictionary:
	return {"id": "mock_test_transport", "live": false}

func send(request_id: int, endpoint: String, headers: PackedStringArray, body: String, timeout_seconds: float) -> Error:
	sent.append({"request_id": request_id, "endpoint": endpoint, "headers": headers.duplicate(), "body": body, "timeout_seconds": timeout_seconds})
	if not synchronous_response.is_empty():
		completed.emit(request_id, 200, synchronous_response, "")
	return send_error

func cancel(request_id: int) -> void:
	cancellations.append(request_id)
	if not cancellation_response.is_empty():
		completed.emit(request_id, 200, cancellation_response, "")

func respond(request_id: int, body: String, http_status := 200, error_code := "") -> void:
	completed.emit(request_id, http_status, body, error_code)
