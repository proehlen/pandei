extends GdUnitTestSuite

## Fake transport: captures written JSON-RPC messages and plays back queued
## server messages on read_available().
class FakeTransport extends AcpTransport:
	var written: Array = []
	var inbox: Array = []
	var _open := false

	func open() -> Error:
		_open = true
		return OK

	func is_open() -> bool:
		return _open

	func close() -> void:
		_open = false

	func write_bytes(data: PackedByteArray) -> Error:
		for line in data.get_string_from_utf8().split("\n"):
			if line.strip_edges() != "":
				written.append(JSON.parse_string(line))
		return OK

	func read_available() -> PackedByteArray:
		var s := ""
		for m in inbox:
			s += JSON.stringify(m) + "\n"
		inbox.clear()
		return s.to_utf8_buffer()


func _make_client() -> Dictionary:
	var t := FakeTransport.new()
	t.open()
	var conn := AcpConnection.new(t)
	var client := AcpClient.new(conn, "/tmp/fake-project")
	return {"transport": t, "connection": conn, "client": client}


func test_initialize_sends_protocol_v1_and_emits_signal() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	var inited: Array = []
	client.initialized.connect(func(r: Dictionary) -> void: inited.append(r))

	client.initialize()
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("initialize")
	assert_that(int(sent[0]["params"]["protocolVersion"])).is_equal(1)
	assert_that(sent[0]["params"]["clientInfo"]["name"]).is_equal("pandei-godot-acp")

	f["transport"].inbox.append({"jsonrpc": "2.0", "id": sent[0]["id"],
		"result": {"protocolVersion": 1, "authMethods": [], "agentInfo": {"name": "vibe", "version": "3.1.4"}}})
	client.pump()
	assert_that(inited).has_size(1)
	assert_that(client.server_info["agentInfo"]["version"]).is_equal("3.1.4")

func test_load_or_new_falls_back_to_new_session() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	var ready_events: Array = []
	client.session_ready.connect(func(sid: String, info: Dictionary) -> void: ready_events.append([sid, info]))

	client.load_or_new("dead-session-id")
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/load")
	assert_that(sent[0]["params"]["sessionId"]).is_equal("dead-session-id")
	assert_that(sent[0]["params"]["cwd"]).is_equal("/tmp/fake-project")
	# regression: session/load requires mcpServers or vibe-acp rejects with -32602
	assert_that(sent[0]["params"]["mcpServers"]).is_equal([])

	# server rejects the load -> client must fall back to session/new
	f["transport"].inbox.append({"jsonrpc": "2.0", "id": sent[0]["id"], "error": {"code": -32602, "message": "no such session"}})
	client.pump()
	assert_that(ready_events).is_empty()
	assert_that(f["transport"].written).has_size(2)
	assert_that(f["transport"].written[1]["method"]).is_equal("session/new")

	f["transport"].inbox.append({"jsonrpc": "2.0", "id": f["transport"].written[1]["id"],
		"result": {"sessionId": "abc-123", "modes": {"currentModeId": "ask", "availableModes": [{"id": "ask", "name": "Ask"}]}}})
	client.pump()
	assert_that(ready_events).has_size(1)
	assert_that(ready_events[0][0]).is_equal("abc-123")
	assert_that(ready_events[0][1]["modes"]["currentModeId"]).is_equal("ask")
	assert_that(client.session_id).is_equal("abc-123")

func test_load_or_new_accepts_load_result_without_session_id() -> void:
	# vibe-acp's session/load response omits sessionId; the requested id is the session
	var f := _make_client()
	var client: AcpClient = f["client"]
	var ready_events: Array = []
	client.session_ready.connect(func(sid: String, _info: Dictionary) -> void: ready_events.append(sid))

	client.load_or_new("sess-to-resume")
	var sent: Array = f["transport"].written
	assert_that(sent[0]["method"]).is_equal("session/load")
	f["transport"].inbox.append({"jsonrpc": "2.0", "id": sent[0]["id"],
		"result": {"modes": {"currentModeId": "ask"}, "configOptions": []}})  # no sessionId key
	client.pump()
	assert_that(ready_events).is_equal(["sess-to-resume"])
	assert_that(client.session_id).is_equal("sess-to-resume")

func test_prompt_streams_updates_then_finishes() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.session_id = "sess-1"
	var updates: Array = []
	var finished: Array = []
	client.session_update.connect(func(sid: String, update: Dictionary) -> void: updates.append([sid, update]))
	client.prompt_finished.connect(func(sid: String, result: Variant, error: Variant) -> void: finished.append([sid, result, error]))

	client.prompt("Say PONG")
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/prompt")
	assert_that(sent[0]["params"]["sessionId"]).is_equal("sess-1")
	assert_that(sent[0]["params"]["prompt"]).is_equal([{"type": "text", "text": "Say PONG"}])
	var req_id: int = sent[0]["id"]

	f["transport"].inbox.append({"jsonrpc": "2.0", "method": "session/update",
		"params": {"sessionId": "sess-1", "update": {"sessionUpdate": "agent_message_chunk", "messageId": "m1", "content": {"type": "text", "text": "PO"}}}})
	f["transport"].inbox.append({"jsonrpc": "2.0", "method": "session/update",
		"params": {"sessionId": "sess-1", "update": {"sessionUpdate": "agent_message_chunk", "messageId": "m1", "content": {"type": "text", "text": "NG"}}}})
	f["transport"].inbox.append({"jsonrpc": "2.0", "id": req_id, "result": {"stopReason": "end_turn"}})
	client.pump()

	assert_that(updates).has_size(2)
	assert_that(updates[0][1]["sessionUpdate"]).is_equal("agent_message_chunk")
	assert_that(updates[1][1]["content"]["text"]).is_equal("NG")
	assert_that(finished).has_size(1)
	assert_that(finished[0][1]).is_equal({"stopReason": "end_turn"})
	assert_that(finished[0][2]).is_null()

func test_prompt_without_session_is_ignored() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.prompt("hello")
	assert_that(f["transport"]["written"]).is_empty()

func test_cancel_sends_session_cancel_as_notification() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.session_id = "sess-9"
	client.cancel()
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/cancel")
	assert_that(sent[0]["params"]["sessionId"]).is_equal("sess-9")
	# ACP defines session/cancel as a notification: no request id, no response.
	# Sent as a request, the agent answers "method not found" and Stop appeared dead.
	assert_that(sent[0].has("id")).is_false()

func test_cancel_without_session_sends_nothing() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.cancel()
	assert_that(f["transport"].written).is_empty()

func test_set_mode_and_config_option() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.session_id = "sess-1"
	client.set_mode("auto-approve")
	client.set_config_option("approval_policy", "auto-approve")
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(2)
	assert_that(sent[0]["method"]).is_equal("session/set_mode")
	assert_that(sent[0]["params"]["modeId"]).is_equal("auto-approve")
	assert_that(sent[1]["method"]).is_equal("session/set_config_option")

func test_read_account_sends_account_read_with_session_id() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.session_id = "sess-1"
	var got: Array = []
	client.account_read.connect(func(r: Dictionary, e: Variant) -> void: got.append([r, e]))

	client.read_account()
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("_account/read")
	assert_that(sent[0]["params"]["sessionId"]).is_equal("sess-1")

	f["transport"].inbox.append({"jsonrpc": "2.0", "id": sent[0]["id"],
		"result": {"status": "ok", "plan": {"kind": "pro", "name": "pro", "title": "PAYG API"},
			"budget": {"usage_percentage": 15.0, "reset_at": "2026-02-01", "payg_enabled": true}}})
	client.pump()
	assert_that(got).has_size(1)
	assert_that(got[0][1]).is_null()
	assert_that(got[0][0]["budget"]["usage_percentage"]).is_equal(15.0)
	assert_that(got[0][0]["plan"]["title"]).is_equal("PAYG API")

func test_read_account_without_session_sends_nothing() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.read_account()
	assert_that(f["transport"].written).is_empty()

func test_read_account_error_emits_error_and_empty_result() -> void:
	var f := _make_client()
	var client: AcpClient = f["client"]
	client.session_id = "sess-1"
	var got: Array = []
	client.account_read.connect(func(r: Dictionary, e: Variant) -> void: got.append([r, e]))
	client.read_account()
	var sent: Array = f["transport"].written
	f["transport"].inbox.append({"jsonrpc": "2.0", "id": sent[0]["id"],
		"error": {"code": -32000, "message": "no billing on this platform"}})
	client.pump()
	assert_that(got).has_size(1)
	assert_that(got[0][0]).is_empty()
	assert_that(str(got[0][1]["message"])).is_equal("no billing on this platform")
