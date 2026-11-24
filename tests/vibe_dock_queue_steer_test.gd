extends GdUnitTestSuite
## Queue/steer contract of VibeAcpDock while a turn is running (mirrors the
## Vibe CLI: submit text to queue it for after the turn; submit again with an
## empty box to steer the first queued message — cancel the current turn and
## send it as the next prompt):
## - Submitting non-empty text while _busy queues it client-side (vibe-acp
##   rejects session/prompt mid-turn, so nothing is sent yet), clears the
##   input and prints a [sys] line.
## - When prompt_finished arrives, the oldest queued message is sent next;
##   the dock stays busy until the queue is empty.
## - Steering pops the first queued message into _steer, sends session/cancel
##   once, and the steered message is sent when the cancelled turn ends.
## - Queue and steer state are cleared on disconnect and on New session.

class FakeTransport extends AcpTransport:
	var written: Array = []
	var _open := true

	func open() -> Error:
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
		return PackedByteArray()


func _make_dock() -> Dictionary:
	var dock := VibeAcpDock.new()
	dock._build_ui()  # controls exist, but _ready()/auto-connect never runs
	var t := FakeTransport.new()
	var client := AcpClient.new(AcpConnection.new(t), "/tmp/fake-project")
	dock.client = client
	return {"dock": dock, "transport": t, "client": client}


func _methods(t: FakeTransport) -> Array:
	var out: Array = []
	for m in t.written:
		out.append(str(m.get("method", "")))
	return out


func _count_method(t: FakeTransport, method: String) -> int:
	return _methods(t).count(method)


## The prompt payloads that were sent, in order.
func _sent_prompts(t: FakeTransport) -> Array:
	var out: Array = []
	for m in t.written:
		if m.get("method", "") == "session/prompt":
			var p: Array = m.get("params", {}).get("prompt", [])
			out.append(str(p[0].get("text", "")) if not p.is_empty() else "")
	return out


func _ready_session(f: Dictionary) -> void:
	f["client"].session_id = "sid-abc123"
	f["dock"]._on_session_ready("sid-abc123", {})


func after_test() -> void:
	# _send_now persists the session id/busy flag in editor settings; don't leak
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)


func test_submit_while_busy_queues_without_sending() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._input.text = "second"
	dock._send_text("second")
	assert_that(_count_method(f["transport"], "session/prompt")).is_equal(1)  # still only the first
	assert_that(dock._queued).is_equal(["second"])
	assert_that(dock._input.text).is_equal("")
	assert_that(dock._busy).is_true()
	assert_that(dock._turn_label.text).is_equal("working… +1 queued")
	assert_that(dock._transcript.get_parsed_text()).contains("queued (1): second")
	f["dock"].free()


func test_queued_message_is_sent_when_turn_ends() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("second")
	dock._send_text("third")
	assert_that(dock._queued).is_equal(["second", "third"])
	dock._on_prompt_finished("sid-abc123", {}, null)  # first turn ends
	assert_that(_sent_prompts(f["transport"])).is_equal(["first", "second"])
	assert_that(dock._queued).is_equal(["third"])
	assert_that(dock._busy).is_true()  # the drained turn is now running
	assert_that(dock._turn_label.text).is_equal("working… +1 queued")
	dock._on_prompt_finished("sid-abc123", {}, null)  # second turn ends
	assert_that(_sent_prompts(f["transport"])).is_equal(["first", "second", "third"])
	assert_that(dock._queued).is_empty()
	dock._on_prompt_finished("sid-abc123", {}, null)  # third turn ends, queue empty
	assert_that(dock._busy).is_false()
	assert_that(dock._turn_label.text).is_equal("idle")
	assert_that(dock._send_btn.disabled).is_false()
	f["dock"].free()


func test_steer_cancels_turn_then_sends_queued_message() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("steer me")
	dock._send_text("")  # empty box while busy + queue non-empty -> steer
	assert_that(_count_method(f["transport"], "session/cancel")).is_equal(1)
	assert_that(dock._steer).is_equal("steer me")
	assert_that(dock._queued).is_empty()
	assert_that(_count_method(f["transport"], "session/prompt")).is_equal(1)  # nothing new yet
	assert_that(dock._cancelling).is_true()
	assert_that(dock._stop_btn.disabled).is_true()  # already cancelling
	dock._on_prompt_finished("sid-abc123", {"stopReason": "cancelled"}, null)  # cancelled turn ends
	assert_that(_sent_prompts(f["transport"])).is_equal(["first", "steer me"])
	assert_that(dock._steer).is_equal("")
	assert_that(dock._busy).is_true()  # steered turn is now running
	assert_that(dock._cancelling).is_false()
	f["dock"].free()


func test_steer_prefers_oldest_queued_message() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("older")
	dock._send_text("newer")
	dock._send_text("")  # steer
	assert_that(dock._steer).is_equal("older")
	assert_that(dock._queued).is_equal(["newer"])
	dock._on_prompt_finished("sid-abc123", {}, null)
	assert_that(_sent_prompts(f["transport"])).is_equal(["first", "older"])
	dock._on_prompt_finished("sid-abc123", {}, null)  # steered turn ends -> remaining queue drains
	assert_that(_sent_prompts(f["transport"])).is_equal(["first", "older", "newer"])
	f["dock"].free()


func test_empty_submit_while_busy_without_queue_is_noop() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("")  # nothing queued, empty box -> no steer, no cancel
	assert_that(_count_method(f["transport"], "session/cancel")).is_equal(0)
	assert_that(dock._steer).is_equal("")
	assert_that(dock._queued).is_empty()
	f["dock"].free()


func test_send_button_label_reflects_queue_steer_mode() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._update_send_state()
	assert_that(dock._send_btn.text).is_equal("Send")
	dock._send_text("first")
	dock._input.text = "more"
	dock._update_send_state()
	assert_that(dock._send_btn.text).is_equal("Queue")
	dock._send_text("more")  # queued, box cleared
	dock._update_send_state()
	assert_that(dock._send_btn.text).is_equal("Steer")
	f["dock"].free()


func test_new_session_clears_queue_and_steer() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("queued msg")
	dock._send_text("")  # steer -> _steer set, _cancelling true
	dock._on_new_session()
	assert_that(dock._queued).is_empty()
	assert_that(dock._steer).is_equal("")
	assert_that(dock._busy).is_false()
	assert_that(dock._cancelling).is_false()
	f["dock"].free()


func test_disconnect_discards_queue() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._send_text("queued msg")
	f["transport"].close()
	dock._handle_disconnect("agent process ended")
	assert_that(dock._queued).is_empty()
	assert_that(dock._busy).is_false()
	assert_that(dock._send_btn.disabled).is_true()
	assert_that(dock._transcript.get_parsed_text()).contains("discarded 1 queued message")
	f["dock"].free()


func test_send_still_blocked_without_session_and_keeps_input() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	dock._update_send_state()
	dock._input.text = "hello"
	dock._send_text("hello")
	assert_that(_methods(f["transport"])).is_empty()
	assert_that(dock._input.text).is_equal("hello")
	assert_that(dock._queued).is_empty()
	f["dock"].free()
