extends GdUnitTestSuite
## Send/Stop button-state contract of VibeAcpDock:
## - Send is enabled exactly when Ctrl+Enter would work (both go through
##   _can_send()), and becomes enabled as soon as a session is ready —
##   previously the button stayed disabled after session_ready until some
##   unrelated state change, while Ctrl+Enter still sent.
## - Stop is enabled only while a turn is in flight; pressing it switches to a
##   busy "Stopping…" state until prompt_finished arrives (session/cancel is a
##   notification, so the turn ends asynchronously), and repeated presses do
##   not spam session/cancel.
## Drives the dock with a fake transport; the UI is built without entering the
## tree so _ready() never spawns a real vibe-acp.

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


## Simulate the server answering session/new: session_id is set and the dock
## runs its session_ready handler.
func _ready_session(f: Dictionary) -> void:
	f["client"].session_id = "sid-abc123"
	f["dock"]._on_session_ready("sid-abc123", {})


func after_test() -> void:
	# _send_text persists the session id/busy flag in editor settings; don't leak
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)


func test_send_disabled_before_session_ready_enabled_on_session_ready() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	dock._update_send_state()
	assert_that(dock._can_send()).is_false()
	assert_that(dock._send_btn.disabled).is_true()  # connected, but no session yet
	_ready_session(f)
	# the reported bug: the button used to stay disabled here while Ctrl+Enter worked
	assert_that(dock._can_send()).is_true()
	assert_that(dock._send_btn.disabled).is_false()
	assert_that(dock._stop_btn.disabled).is_true()  # idle: nothing to stop
	f["dock"].free()


func test_ctrl_enter_noops_without_session_and_button_agrees() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	dock._update_send_state()
	dock._input.text = "please analyze the project"
	dock._send_text("please analyze the project")  # what Ctrl+Enter calls
	# prompt() would silently drop the text (no session_id), so nothing may be
	# sent, the input must not be eaten and _busy must not get stuck
	assert_that(_methods(f["transport"])).is_empty()
	assert_that(dock._input.text).is_equal("please analyze the project")
	assert_that(dock._busy).is_false()
	assert_that(dock._send_btn.disabled).is_true()  # button agrees with Ctrl+Enter
	f["dock"].free()


func test_send_text_sends_prompt_and_flips_buttons() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._input.text = "hello"
	dock._send_text("hello")
	assert_that(_count_method(f["transport"], "session/prompt")).is_equal(1)
	assert_that(dock._busy).is_true()
	assert_that(dock._input.text).is_equal("")
	assert_that(dock._send_btn.disabled).is_true()   # busy: Send off
	assert_that(dock._stop_btn.disabled).is_false()  # busy: Stop on
	f["dock"].free()


func test_ctrl_enter_while_busy_is_blocked_and_keeps_input() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("first")
	dock._input.text = "second"
	dock._send_text("second")  # Ctrl+Enter during a running turn
	assert_that(_count_method(f["transport"], "session/prompt")).is_equal(1)
	assert_that(dock._input.text).is_equal("second")  # kept, not sent or eaten
	assert_that(dock._send_btn.disabled).is_true()
	assert_that(dock._stop_btn.disabled).is_false()
	f["dock"].free()


func test_stop_sends_cancel_notification_once_and_shows_busy() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("hi")
	var before: int = f["transport"].written.size()
	dock._on_stop()
	var cancels: Array = f["transport"].written.slice(before).filter(
		func(m: Dictionary) -> bool: return m.get("method", "") == "session/cancel")
	assert_that(cancels).has_size(1)
	assert_that(cancels[0].has("id")).is_false()  # notification: no response expected
	assert_that(dock._cancelling).is_true()
	assert_that(dock._stop_btn.disabled).is_true()  # busy: no repeated presses
	assert_that(dock._stop_btn.text).is_equal("Stopping…")
	assert_that(dock._send_btn.disabled).is_true()
	assert_that(dock._turn_label.text).is_equal("stopping…")
	dock._on_stop()  # second press while cancelling must be a no-op
	assert_that(_count_method(f["transport"], "session/cancel")).is_equal(1)
	f["dock"].free()


func test_stop_disabled_when_idle_or_disconnected() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	dock._update_send_state()
	assert_that(dock._stop_btn.disabled).is_true()  # no client session yet
	_ready_session(f)
	assert_that(dock._stop_btn.disabled).is_true()  # idle: nothing to stop
	f["transport"].close()
	dock._update_send_state()
	assert_that(dock._stop_btn.disabled).is_true()  # disconnected
	assert_that(dock._send_btn.disabled).is_true()
	f["dock"].free()


func test_prompt_finished_after_stop_reenables_send_and_disables_stop() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("hi")
	dock._on_stop()
	dock._on_prompt_finished("sid-abc123", {}, null)  # server ends the turn
	assert_that(dock._busy).is_false()
	assert_that(dock._cancelling).is_false()
	assert_that(dock._send_btn.disabled).is_false()
	assert_that(dock._stop_btn.disabled).is_true()
	assert_that(dock._stop_btn.text).is_equal("Stop")
	assert_that(dock._turn_label.text).is_equal("idle")
	f["dock"].free()


func test_disconnect_while_cancelling_resets_buttons() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("hi")
	dock._on_stop()
	f["transport"].close()  # simulate the agent process dying mid-cancel
	dock._handle_disconnect("agent process ended")
	assert_that(dock._busy).is_false()
	assert_that(dock._cancelling).is_false()
	assert_that(dock._send_btn.disabled).is_true()
	assert_that(dock._stop_btn.disabled).is_true()
	assert_that(dock._stop_btn.text).is_equal("Stop")
	f["dock"].free()


func test_new_session_resets_cancelling() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._send_text("hi")
	dock._on_stop()
	dock._on_new_session()
	assert_that(dock._cancelling).is_false()
	assert_that(dock._stop_btn.disabled).is_true()
	assert_that(_count_method(f["transport"], "session/new")).is_equal(1)
	f["dock"].free()


func test_no_client_means_both_buttons_disabled() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock.client = null
	dock._update_send_state()
	assert_that(dock._can_send()).is_false()
	assert_that(dock._can_stop()).is_false()
	assert_that(dock._send_btn.disabled).is_true()
	assert_that(dock._stop_btn.disabled).is_true()
	dock.free()
