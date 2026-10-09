extends Node
## Single-use HTTPS transport. No redirect, retry, persistence, logging or tools.
signal completed(request_id: int, http_status: int, body: String, error_code: String)
const MAX_RESPONSE_BYTES := 524288
var _requests: Dictionary = {}

func info() -> Dictionary: return {"id": "openai_compatible_http", "live": true}

func send(request_id: int, endpoint: String, headers: PackedStringArray, body: String, timeout_seconds: float) -> Error:
	if not is_inside_tree() or _requests.has(request_id): return ERR_BUSY
	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	http.max_redirects = 0 # Never forward Authorization to redirected destinations.
	http.body_size_limit = MAX_RESPONSE_BYTES
	http.accept_gzip = true
	add_child(http)
	_requests[request_id] = http
	http.request_completed.connect(_on_completed.bind(request_id), CONNECT_ONE_SHOT)
	var error := http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_requests.erase(request_id); http.queue_free()
	return error

func cancel(request_id: int) -> void:
	if not _requests.has(request_id): return
	var http: HTTPRequest = _requests[request_id]
	_requests.erase(request_id)
	http.cancel_request(); http.queue_free()

func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	if not _requests.has(request_id): return
	var http: HTTPRequest = _requests[request_id]
	_requests.erase(request_id); http.queue_free()
	var error := ""
	if result == HTTPRequest.RESULT_TIMEOUT: error = "TIMEOUT"
	elif result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: error = "RESPONSE_TOO_LARGE"
	elif result != HTTPRequest.RESULT_SUCCESS: error = "NETWORK_ERROR"
	completed.emit(request_id, response_code, body.get_string_from_utf8() if error.is_empty() else "", error)

func _exit_tree() -> void:
	for request_id in _requests.keys(): cancel(request_id)
