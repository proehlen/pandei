class_name AcpDispatcher
extends RefCounted
## Routes incoming JSON-RPC messages:
##   - response (has id, no method)  -> pending request callbacks
##   - notification (method, no id)  -> registered notification handlers
##   - request (method + id)         -> registered request handlers; the
##     handler receives (params, respond) and must eventually call
##     respond.call(result) or respond.call(null, error_dict).
## UI-free and synchronous, so tests can drive it with handle_message().

signal response_received(id: int, result: Variant, error: Variant)
signal notification_received(method: String, params: Variant)
signal request_received(method: String, id: int, params: Variant)

var _pending: Dictionary = {}
var _request_handlers: Dictionary = {}
var _notification_handlers: Dictionary = {}

func register_response_handler(id: int, handler: Callable) -> void:
	_pending[id] = handler

func cancel_response_handler(id: int) -> void:
	_pending.erase(id)

func register_request_handler(method: String, handler: Callable) -> void:
	_request_handlers[method] = handler

func has_request_handler(method: String) -> bool:
	return _request_handlers.has(method)

func register_notification_handler(method: String, handler: Callable) -> void:
	if not _notification_handlers.has(method):
		_notification_handlers[method] = []
	_notification_handlers[method].append(handler)

## send_fn: Callable(Dictionary) used to write replies onto the wire.
func handle_message(msg: Dictionary, send_fn: Callable) -> void:
	var msg_has_method := msg.has("method")
	var has_id := msg.has("id")
	if msg_has_method and has_id:
		var method := str(msg["method"])
		var id: int = msg["id"]
		var params: Variant = msg.get("params", {})
		request_received.emit(method, id, params)
		if _request_handlers.has(method):
			var handler: Callable = _request_handlers[method]
			handler.call(params, func(result: Variant, error: Variant = null) -> void:
				if error != null:
					send_fn.call({"jsonrpc": "2.0", "id": id, "error": error})
				else:
					send_fn.call({"jsonrpc": "2.0", "id": id, "result": result if result != null else {}})
			)
		else:
			send_fn.call({"jsonrpc": "2.0", "id": id,
				"error": {"code": -32601, "message": "Method not found: " + method}})
	elif has_id:
		var id: int = msg["id"]
		var result: Variant = msg.get("result")
		var error: Variant = msg.get("error")
		response_received.emit(id, result, error)
		if _pending.has(id):
			var handler: Callable = _pending[id]
			_pending.erase(id)
			handler.call(result, error)
	elif msg_has_method:
		var method := str(msg["method"])
		var params: Variant = msg.get("params", {})
		notification_received.emit(method, params)
		if _notification_handlers.has(method):
			for handler in _notification_handlers[method]:
				handler.call(params)
