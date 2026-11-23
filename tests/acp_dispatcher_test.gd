extends GdUnitTestSuite

func _sent_capture() -> Dictionary:
	var sent: Array = []
	return {"sent": sent, "send_fn": func(m: Dictionary) -> void: sent.append(m)}

func test_response_dispatches_to_pending_handler() -> void:
	var d := AcpDispatcher.new()
	var got: Array = []
	d.register_response_handler(7, func(result: Variant, error: Variant) -> void: got.append([result, error]))
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "id": 7, "result": {"ok": true}}, cap["send_fn"])
	assert_that(got).is_equal([[{"ok": true}, null]])
	assert_that(cap["sent"]).is_empty()

func test_response_error_is_forwarded() -> void:
	var d := AcpDispatcher.new()
	var got: Array = []
	d.register_response_handler(3, func(result: Variant, error: Variant) -> void: got.append([result, error]))
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "id": 3, "error": {"code": -32600, "message": "bad"}}, cap["send_fn"])
	assert_that(got[0][0]).is_null()
	assert_that(got[0][1]).is_equal({"code": -32600, "message": "bad"})

func test_notification_routed_to_registered_handlers() -> void:
	var d := AcpDispatcher.new()
	var got: Array = []
	d.register_notification_handler("session/update", func(params: Variant) -> void: got.append(params))
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s", "update": {}}}, cap["send_fn"])
	assert_that(got).is_equal([{"sessionId": "s", "update": {}}])
	assert_that(cap["sent"]).is_empty()

func test_server_request_handler_can_respond_later() -> void:
	var d := AcpDispatcher.new()
	var box: Array = []  # lambdas capture by value, so use a mutable box
	d.register_request_handler("session/request_permission", func(_params: Variant, respond: Callable) -> void:
		box.append(respond))
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "id": 9, "method": "session/request_permission", "params": {"options": []}}, cap["send_fn"])
	assert_that(cap["sent"]).is_empty()  # async response: nothing sent yet
	assert_that(box).has_size(1)
	box[0].call({"outcome": {"outcome": "selected", "optionId": "allow"}})
	assert_that(cap["sent"]).has_size(1)
	assert_that(cap["sent"][0]["id"]).is_equal(9)
	assert_that(cap["sent"][0]["result"]).is_equal({"outcome": {"outcome": "selected", "optionId": "allow"}})

func test_server_request_error_response() -> void:
	var d := AcpDispatcher.new()
	d.register_request_handler("fs/write_text_file", func(_params: Variant, respond: Callable) -> void:
		respond.call(null, {"code": -32001, "message": "denied"}))
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "id": 4, "method": "fs/write_text_file", "params": {}}, cap["send_fn"])
	assert_that(cap["sent"]).has_size(1)
	assert_that(cap["sent"][0]["error"]).is_equal({"code": -32001, "message": "denied"})

func test_unknown_server_request_gets_method_not_found() -> void:
	var d := AcpDispatcher.new()
	var cap := _sent_capture()
	d.handle_message({"jsonrpc": "2.0", "id": 5, "method": "terminal/create", "params": {}}, cap["send_fn"])
	assert_that(cap["sent"]).has_size(1)
	assert_that(int(cap["sent"][0]["error"]["code"])).is_equal(-32601)
