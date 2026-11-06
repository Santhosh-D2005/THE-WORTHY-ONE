class_name HttpTransport
extends Node
## The one place that touches the network: sends a request with HTTPRequest and returns {"status": int, "body": String, "error": String}.
## error is "" on any HTTP answer (including 4xx/5xx: the caller reads the status) and one of "offline", "timeout", "network" when no answer
## arrived. Tests replace Backend.transport with a scripted one; nothing else in the game uses HTTPRequest.

func send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = BackendConfig.TIMEOUT_SECONDS
	add_child(http)
	var started := http.request(url, headers, method, body)
	if started != OK:
		http.queue_free()
		return {"status": 0, "body": "", "error": "offline"}
	var finished: Array = await http.request_completed
	http.queue_free()
	var result: int = finished[0]
	var status: int = finished[1]
	var bytes: PackedByteArray = finished[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": "", "error": error_for_result(result)}
	return {"status": status, "body": bytes.get_string_from_utf8(), "error": ""}

static func error_for_result(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, \
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_NO_RESPONSE:
			return "offline"
		_:
			return "network"
