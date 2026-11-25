class_name AcpClient
extends RefCounted
## High-level ACP client for vibe-acp. UI-free: the dock drives it via
## pump() and consumes its signals. Testable with a fake transport.

const PROTOCOL_VERSION := 1

signal initialized(result: Dictionary)
signal auth_methods_available(methods: Array)
signal session_ready(session_id: String, info: Dictionary)
signal session_error(message: String)
signal session_load_failed(session_id: String, error: Variant)
signal sessions_listed(sessions: Array)
signal prompt_finished(session_id: String, result: Variant, error: Variant)
signal session_update(session_id: String, update: Dictionary)
signal account_read(result: Dictionary, error: Variant)
signal log_line(text: String)

var connection: AcpConnection
var dispatcher: AcpDispatcher
var project_root: String = ""
var session_id: String = ""
var server_info: Dictionary = {}
var auth_methods: Array = []

func _init(p_connection: AcpConnection, p_project_root: String = "") -> void:
	connection = p_connection
	project_root = p_project_root
	dispatcher = AcpDispatcher.new()
	dispatcher.register_notification_handler("session/update", _on_session_update)

func is_open() -> bool:
	return connection != null and connection.is_open()

## Pump pending bytes through the dispatcher. Call every frame.
func pump() -> void:
	if connection == null:
		return
	for msg in connection.poll():
		dispatcher.handle_message(msg, func(m: Dictionary) -> void:
			connection.send(m))

func initialize() -> void:
	_send_request("initialize", {
		"protocolVersion": PROTOCOL_VERSION,
		"clientInfo": {
			"name": "pandei-godot-acp",
			"title": "pandei (Godot editor)",
			"version": "0.1.0",
		},
		"capabilities": {},
	}, func(result: Variant, error: Variant) -> void:
		if error == null and result is Dictionary:
			server_info = result
			auth_methods = result.get("authMethods", [])
			if auth_methods.size() > 0:
				auth_methods_available.emit(auth_methods)
			initialized.emit(result)
		else:
			log_line.emit("initialize failed: " + str(error))
	)

## Load an existing session, falling back to a fresh one on any error.
func load_or_new(p_session_id: String) -> void:
	if p_session_id.is_empty():
		new_session()
		return
	# ACP requires mcpServers on session/load too (pydantic "Field required"),
	# otherwise every resume is rejected with -32602 and we fall back to new.
	_send_request("session/load", {"sessionId": p_session_id, "cwd": project_root, "mcpServers": []},
		func(result: Variant, error: Variant) -> void:
			# vibe-acp's session/load result carries modes/configOptions but does
			# not echo sessionId, so fall back to the id we asked to load.
			if error == null and result is Dictionary:
				session_id = str(result.get("sessionId", p_session_id))
				session_ready.emit(session_id, result)
			else:
				session_load_failed.emit(p_session_id, error)
				log_line.emit("Could not resume session %s (%s); starting a new one." % [p_session_id, _fmt_error(error)])
				new_session()
	)

func new_session() -> void:
	_send_request("session/new", {"cwd": project_root, "mcpServers": []},
		func(result: Variant, error: Variant) -> void:
			if error == null and result is Dictionary and str(result.get("sessionId", "")) != "":
				session_id = str(result["sessionId"])
				session_ready.emit(session_id, result)
			else:
				session_error.emit("session/new failed: " + str(error))
	)

func list_sessions() -> void:
	_send_request("session/list", {"cwd": project_root},
		func(result: Variant, error: Variant) -> void:
			if error == null and result is Dictionary:
				sessions_listed.emit(result.get("sessions", []))
			else:
				log_line.emit("session/list failed: " + str(error))
	)

func prompt(text: String) -> void:
	if session_id.is_empty() or text.strip_edges().is_empty():
		return
	_send_request("session/prompt", {
		"sessionId": session_id,
		"prompt": [{"type": "text", "text": text}],
	}, func(result: Variant, error: Variant) -> void:
		prompt_finished.emit(session_id, result, error)
	)

## ACP defines session/cancel as a *notification* (no id, no response expected).
## Sending it as a request made the agent answer "method not found" and the
## Stop button appeared dead while the turn kept running.
func cancel() -> void:
	if session_id.is_empty():
		return
	if connection == null or not connection.is_open():
		return
	connection.send({"jsonrpc": "2.0", "method": "session/cancel", "params": {"sessionId": session_id}})

func set_mode(mode_id: String) -> void:
	if session_id.is_empty() or mode_id.is_empty():
		return
	_send_request("session/set_mode", {"sessionId": session_id, "modeId": mode_id},
		func(_result: Variant, _error: Variant) -> void: pass)

func set_config_option(config_id: String, value: Variant) -> void:
	if session_id.is_empty():
		return
	_send_request("session/set_config_option", {
		"sessionId": session_id, "configId": config_id, "value": value,
	}, func(_result: Variant, _error: Variant) -> void: pass)

func authenticate(method_id: String) -> void:
	_send_request("authenticate", {"methodId": method_id},
		func(result: Variant, error: Variant) -> void:
			if error == null:
				log_line.emit("Authenticated.")
				if result is Dictionary:
					initialized.emit(result)
			else:
				log_line.emit("authenticate failed: " + str(error))
	)

## vibe extension (not in the ACP spec): account/read returns the AccountView —
## plan (name/title, e.g. "PAYG API") and budget (usage_percentage, reset_at,
## payg_enabled) read from the billing API. Needs a live session id; on
## self-hosted platforms the billing fields may be absent.
## Wire name is "_account/read": the ACP router only forwards methods with a
## leading "_" to the agent's ext_method and strips exactly that one "_", so a
## bare "account/read" gets -32601 "Method not found" and "_/account/read"
## arrives as "/account/read" (-32601 "Method not implemented").
func read_account() -> void:
	if session_id.is_empty():
		return
	_send_request("_account/read", {"sessionId": session_id},
		func(result: Variant, error: Variant) -> void:
			if error == null and result is Dictionary:
				account_read.emit(result, null)
			else:
				account_read.emit({}, error))

func _send_request(method: String, params: Dictionary, on_response: Callable) -> void:
	if connection == null or not connection.is_open():
		on_response.call(null, {"code": -32000, "message": "not connected"})
		return
	var id := connection.next_request_id()
	dispatcher.register_response_handler(id, on_response)
	var err := connection.send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
	if err != OK:
		dispatcher.cancel_response_handler(id)
		on_response.call(null, {"code": err, "message": "send failed: %d" % err})

func _on_session_update(params: Variant) -> void:
	if params is Dictionary:
		session_update.emit(str(params.get("sessionId", "")), params.get("update", {}))

## Compact one-line rendering of a JSON-RPC error (Dictionary) or any value.
static func _fmt_error(error: Variant) -> String:
	if error is Dictionary:
		var code: Variant = error.get("code", "")
		var message: Variant = error.get("message", "")
		if str(message) != "":
			return "%s (%s)" % [message, code] if str(code) != "" else str(message)
	return str(error)
