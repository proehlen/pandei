extends GdUnitTestSuite

func test_encode_message_appends_newline_and_valid_json() -> void:
	var bytes := AcpCodec.encode_message({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
	var s := bytes.get_string_from_utf8()
	assert_that(s.ends_with("\n")).is_true()
	var parsed: Dictionary = JSON.parse_string(s.strip_edges())
	assert_that(parsed["jsonrpc"]).is_equal("2.0")
	assert_that(int(parsed["id"])).is_equal(1)
	assert_that(parsed["method"]).is_equal("initialize")

func test_line_buffer_returns_complete_lines_only() -> void:
	var buf := AcpCodec.LineBuffer.new()
	var lines: Array = buf.push('{"a":1}\n{"b":'.to_utf8_buffer())
	assert_that(lines).is_equal(['{"a":1}'])
	assert_that(buf.pending_bytes() > 0).is_true()
	lines = buf.push('2}\n'.to_utf8_buffer())
	assert_that(lines).is_equal(['{"b":2}'])
	assert_that(buf.pending_bytes()).is_equal(0)

func test_line_buffer_handles_multiple_lines_and_blank_lines() -> void:
	var buf := AcpCodec.LineBuffer.new()
	var lines: Array = buf.push('{"x":1}\n\n{"x":2}\n'.to_utf8_buffer())
	assert_that(lines).is_equal(['{"x":1}', '{"x":2}'])

func test_line_buffer_handles_crlf() -> void:
	var buf := AcpCodec.LineBuffer.new()
	var lines: Array = buf.push('{"x":1}\r\n'.to_utf8_buffer())
	assert_that(lines).is_equal(['{"x":1}'])
