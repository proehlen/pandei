extends GdUnitTestSuite
## Billing poll contract of VibeAcpDock (account/read — plan + monthly budget,
## what the vibe CLI status bar shows as "PAYG 15%"):
## - one account/read per session_ready so the bar shows the plan immediately;
## - afterwards the 60s timer only fires a request when a usage_update landed
##   within the last minute (no activity -> no server call);
## - a poll already in flight is never duplicated;
## - the answer renders as "<plan> <pct>%" next to the token usage, errors keep
##   the last good value (billing endpoints are optional on self-hosted platforms).
## Drives the dock with a fake transport; the UI is built without entering the
## tree so _ready() never spawns a real vibe-acp.

class FakeTransport extends AcpTransport:
	var written: Array = []
	var inbox: Array = []
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
		var s := ""
		for m in inbox:
			s += JSON.stringify(m) + "\n"
		inbox.clear()
		return s.to_utf8_buffer()


func _make_dock() -> Dictionary:
	var dock := VibeAcpDock.new()
	dock._build_ui()  # controls exist, but _ready()/auto-connect never runs
	var t := FakeTransport.new()
	var client := AcpClient.new(AcpConnection.new(t), "/tmp/fake-project")
	dock.client = client
	dock._wire_client()  # connect signals, so account_read reaches the dock
	return {"dock": dock, "transport": t, "client": client}


func _count_method(t: FakeTransport, method: String) -> int:
	var n := 0
	for m in t.written:
		if str(m.get("method", "")) == method:
			n += 1
	return n


## Simulate the server answering session/new: session_id is set, the dock runs
## its session_ready handler (which sends the one initial account/read), and we
## answer that request too so no poll stays in flight.
func _ready_session(f: Dictionary) -> void:
	f["client"].session_id = "sid-abc123"
	f["dock"]._on_session_ready("sid-abc123", {})
	for m in f["transport"].written:
		if m.get("method", "") == "_/account/read":
			# answer with a valid but plan/budget-less AccountView (self-hosted
			# platform shape): clears the in-flight flag without setting a label
			f["transport"].inbox.append({"jsonrpc": "2.0", "id": m["id"], "result": {"status": "ok"}})
	f["client"].pump()


func _send_usage(dock: VibeAcpDock, used: int, size: int) -> void:
	dock._render_update("sid-abc123", {"sessionUpdate": "usage_update", "used": used, "size": size})


func after_test() -> void:
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)
	VibeAcpSettings.set_auto_connect(true)  # the error-log test disables it to enter the tree


func test_should_poll_account_pure_logic() -> void:
	var now := 1_000_000
	var interval := 60_000
	# live session + tokens used 30s ago -> poll
	assert_that(VibeAcpDock._should_poll_account(now, now - 30_000, interval, true)).is_true()
	# boundary: exactly one interval ago still counts
	assert_that(VibeAcpDock._should_poll_account(now, now - interval, interval, true)).is_true()
	# use older than the interval -> no call (don't hit the billing API while idle)
	assert_that(VibeAcpDock._should_poll_account(now, now - interval - 1, interval, true)).is_false()
	# never used anything -> no call
	assert_that(VibeAcpDock._should_poll_account(now, 0, interval, true)).is_false()
	# no live session -> no call, regardless of usage
	assert_that(VibeAcpDock._should_poll_account(now, now - 1, interval, false)).is_false()


func test_session_ready_sends_exactly_one_initial_account_read() -> void:
	var f := _make_dock()
	_ready_session(f)
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(1)
	assert_that(f["dock"]._account_poll_in_flight).is_false()  # answered above
	f["dock"].free()


func test_poll_tick_without_any_use_sends_nothing() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)  # sends the initial read; _last_usage_change_ms stays 0
	dock._on_account_poll_tick()
	dock._on_account_poll_tick()
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(1)
	f["dock"].free()


func test_poll_tick_after_recent_use_sends_one_more_request() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 1234, 200000)  # marks _last_usage_change_ms = now
	dock._on_account_poll_tick()
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(2)
	f["dock"].free()


func test_poll_tick_with_stale_use_sends_nothing() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 1234, 200000)
	dock._last_usage_change_ms = Time.get_ticks_msec() - 61_000  # older than the interval
	dock._on_account_poll_tick()
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(1)
	f["dock"].free()


func test_poll_in_flight_is_not_duplicated() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 100, 200000)
	dock._on_account_poll_tick()  # sends, stays in flight until the answer arrives
	dock._on_account_poll_tick()  # must not send a second one
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(2)
	assert_that(dock._account_poll_in_flight).is_true()
	f["dock"].free()


func test_poll_tick_without_session_sends_nothing() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	dock._last_usage_change_ms = Time.get_ticks_msec()  # use, but no session/connection
	dock._on_account_poll_tick()
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(0)
	f["dock"].free()


func test_usage_update_renders_tokens_and_marks_activity() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	assert_that(dock._usage_label.text).is_empty()
	_send_usage(dock, 1234, 200000)
	assert_that(dock._usage_label.text).is_equal("1234/200000 tok")
	assert_that(dock._last_usage_change_ms).is_not_equal(0)
	f["dock"].free()


func test_account_read_response_appends_plan_and_budget_to_usage_label() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 1234, 200000)
	dock._on_account_read({
		"plan": {"kind": "pro", "name": "pro", "title": "PAYG API"},
		"budget": {"usage_percentage": 15.4, "reset_at": "2026-02-01", "payg_enabled": true},
	}, null)
	assert_that(dock._budget_text).is_equal("PAYG API 15%")
	assert_that(dock._usage_label.text).is_equal("1234/200000 tok · PAYG API 15%")
	assert_that(dock._usage_label.tooltip_text).contains("resets 2026-02-01")
	assert_that(dock._account_poll_in_flight).is_false()
	f["dock"].free()


func test_account_read_budget_without_plan_title_falls_back_to_payg_flag() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._on_account_read({"budget": {"usage_percentage": 7.0, "payg_enabled": true}}, null)
	assert_that(dock._budget_text).is_equal("PAYG 7%")
	dock._on_account_read({"budget": {"usage_percentage": 8.0, "payg_enabled": false}}, null)
	assert_that(dock._budget_text).is_equal("8%")
	assert_that(dock._usage_label.text).is_equal("8%")  # no tokens yet -> budget only
	f["dock"].free()


func test_account_read_error_keeps_last_good_budget() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	dock._on_account_read({"plan": {"title": "PAYG API"}, "budget": {"usage_percentage": 15.0}}, null)
	dock._on_account_read({}, {"code": -32000, "message": "no billing here"})
	assert_that(dock._budget_text).is_equal("PAYG API 15%")
	assert_that(dock._account_poll_in_flight).is_false()
	f["dock"].free()


func test_account_read_without_budget_changes_nothing() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 50, 200000)
	dock._on_account_read({"status": "ok"}, null)  # self-hosted platform: no plan/budget keys
	assert_that(dock._budget_text).is_empty()
	assert_that(dock._usage_label.text).is_equal("50/200000 tok")
	f["dock"].free()


func test_account_read_plan_without_budget_still_shows_plan_title() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	# budget needs the see_org_inference_usage permission and can be absent;
	# the plan title (what the CLI renders as "PAYG API") must still show
	dock._on_account_read({"plan": {"kind": "pro", "name": "pro", "title": "PAYG API"}}, null)
	assert_that(dock._budget_text).is_equal("PAYG API")
	assert_that(dock._usage_label.text).is_equal("PAYG API")
	f["dock"].free()


func test_account_read_error_logs_to_transcript_once_per_session() -> void:
	# enter the tree (with auto-connect off) so the RichTextLabel actually parses
	VibeAcpSettings.set_auto_connect(false)
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	add_child(dock)
	await get_tree().process_frame
	_ready_session(f)
	var err := {"code": -32000, "message": "no billing here"}
	dock._on_account_read({}, err)
	dock._on_account_read({}, err)  # second failure must not spam the transcript
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.split("account/read failed").size() - 1).is_equal(1)
	assert_that(parsed).contains("no billing here")
	assert_that(dock._account_poll_in_flight).is_false()
	dock.queue_free()


func test_disconnect_clears_usage_and_budget_and_stops_polling() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	_ready_session(f)
	_send_usage(dock, 999, 200000)
	dock._on_account_read({"plan": {"title": "PAYG API"}, "budget": {"usage_percentage": 15.0}}, null)
	f["transport"].close()  # agent process died
	dock._handle_disconnect("agent process ended")
	assert_that(dock._usage_label.text).is_empty()
	assert_that(dock._budget_text).is_empty()
	assert_that(dock._last_usage_change_ms).is_equal(0)
	dock._last_usage_change_ms = Time.get_ticks_msec()  # even forced, no session -> no call
	f["client"].session_id = ""
	dock._on_account_poll_tick()
	assert_that(_count_method(f["transport"], "_/account/read")).is_equal(1)
	f["dock"].free()
