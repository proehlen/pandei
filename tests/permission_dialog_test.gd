extends GdUnitTestSuite
## Regression tests for the ACP permission dialog:
##  1. The dialog must stay fully on screen (OK button reachable without
##     dragging/resizing) even for huge payloads — previously the raw JSON
##     label inflated the window past the screen height.
##  2. A hash-only toolCallId in session/request_permission must be resolved
##     via the tool_call updates seen earlier (known_by_id) into a readable
##     summary of what is actually being approved.

func after_test() -> void:
	# _on_new_session persists empty session state in editor settings; don't leak
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)

# ---------------------------------------------------------------- PermissionText (pure)

func test_summarize_resolves_hash_only_request_via_known_tool_call() -> void:
	var known := {"effect-abc123": {"toolCallId": "effect-abc123", "title": "run a tool",
		"kind": "execute", "rawInput": {"command": "godot --headless --check-only"}}}
	var text := PermissionText.summarize({"toolCallId": "effect-abc123"}, known)
	assert_that(text).contains("Tool: run a tool")
	assert_that(text).contains("Kind: execute")
	assert_that(text).contains("Command: godot --headless --check-only")
	assert_that(text).contains("effect-abc123")

func test_summarize_hash_only_without_known_update_falls_back_to_readable_text() -> void:
	var text := PermissionText.summarize({"toolCallId": "effect-4a1cb37b-c42b-574b-8db4-415aec780948"})
	assert_that(text).contains("a tool call")
	assert_that(text).contains("Tool call ID: effect-4a1cb…0948")
	assert_that(text.contains("415aec780948")).is_false()  # header shows only the shortened id

func test_summarize_shows_file_path_and_content_size_for_edit_tools() -> void:
	var tc := {"toolCallId": "t1", "title": "write file", "kind": "edit",
		"rawInput": {"path": "res://src/x.gd", "content": "abc"}}
	var text := PermissionText.summarize(tc)
	assert_that(text).contains("File: res://src/x.gd (3 chars of content)")

func test_summarize_shows_locations() -> void:
	var tc := {"toolCallId": "t2", "title": "read file", "kind": "read",
		"locations": [{"path": "res://src/core/main.gd", "line": 12}]}
	var text := PermissionText.summarize(tc)
	assert_that(text).contains("Locations: res://src/core/main.gd:12")

func test_request_fields_win_over_known_update() -> void:
	var known := {"t9": {"toolCallId": "t9", "title": "old title"}}
	var text := PermissionText.summarize({"toolCallId": "t9", "title": "new title"}, known)
	assert_that(text).contains("Tool: new title")
	assert_that(text.contains("old title")).is_false()

func test_raw_json_is_capped_and_marked_truncated() -> void:
	var tc := {"toolCallId": "t", "rawInput": {"command": "x".repeat(5000)}}
	var raw := PermissionText.raw_json(tc)
	assert_that(float(raw.length())).is_less_equal(float(PermissionText.RAW_JSON_CAP + 16))
	assert_that(raw).contains("truncated")

func test_raw_json_merges_known_update_so_hash_request_shows_payload() -> void:
	var known := {"effect-z": {"toolCallId": "effect-z", "title": "run a tool", "rawInput": {"command": "ls"}}}
	var raw := PermissionText.raw_json({"toolCallId": "effect-z"}, known)
	assert_that(raw).contains("run a tool")
	assert_that(raw).contains("ls")

# ---------------------------------------------------------------- VibePermissionDialog (UI)

func test_dialog_summary_resolves_hash_via_known_by_id() -> void:
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	var known := {"effect-abc123": {"toolCallId": "effect-abc123", "title": "run a tool",
		"kind": "execute", "rawInput": {"command": "ls -la"}}}
	dlg.setup_dialog({"toolCallId": "effect-abc123"}, [{"optionId": "once", "name": "Allow once"}], known)
	assert_that(dlg._summary.text).contains("Tool: run a tool")
	assert_that(dlg._summary.text).contains("Command: ls -la")
	assert_that(dlg._raw.text).contains("run a tool")  # raw payload merged too
	dlg.queue_free()

func test_dialog_min_height_stays_bounded_for_huge_payload() -> void:
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog({"toolCallId": "effect-huge", "title": "run a tool", "kind": "execute",
		"rawInput": {"command": "echo " + "y".repeat(20000)}},
		[{"optionId": "once", "name": "Allow once"}], {})
	await get_tree().process_frame
	# the raw payload lives in a bounded scroll area, so content min height
	# stays small no matter how big the toolCall is
	assert_that(dlg.get_contents_minimum_size().y).is_less(420.0)
	dlg.queue_free()
	await get_tree().process_frame

func test_popup_on_screen_keeps_whole_dialog_inside_viewport() -> void:
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog({"toolCallId": "effect-huge", "rawInput": {"command": "y".repeat(20000)}},
		[{"optionId": "once", "name": "Allow once"}], {})
	dlg.popup_on_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := Vector2i(get_tree().root.get_visible_rect().size)
	if screen.x <= 0 or screen.y <= 0:
		screen = Vector2i(1024, 600)
	assert_that(dlg.visible).is_true()
	assert_that(float(dlg.size.x)).is_less_equal(float(screen.x))
	assert_that(float(dlg.size.y)).is_less_equal(float(screen.y))
	assert_that(float(dlg.position.x)).is_greater_equal(0.0)
	assert_that(float(dlg.position.y)).is_greater_equal(0.0)
	assert_that(float(dlg.position.x + dlg.size.x)).is_less_equal(float(screen.x + 1))
	assert_that(float(dlg.position.y + dlg.size.y)).is_less_equal(float(screen.y + 1))
	dlg.queue_free()
	await get_tree().process_frame

func test_ok_button_emits_selected_option_exactly_once() -> void:
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog({"toolCallId": "t"}, [
		{"optionId": "allow-once", "name": "Allow once"},
		{"optionId": "cancel", "name": "Cancel"}], {})
	var got: Array = []
	dlg.resolved.connect(func(option_id: String, cancelled: bool) -> void: got.append([option_id, cancelled]))
	dlg.get_ok_button().pressed.emit()  # Button has no press() in 4.x; emit the signal
	dlg.get_ok_button().pressed.emit()  # second press must not re-emit
	assert_that(got).is_equal([["allow-once", false]])
	dlg.queue_free()
	await get_tree().process_frame

func test_cancel_emits_cancelled() -> void:
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog({"toolCallId": "t"}, [{"optionId": "allow-once", "name": "Allow once"}], {})
	var got: Array = []
	dlg.resolved.connect(func(option_id: String, cancelled: bool) -> void: got.append([option_id, cancelled]))
	dlg.canceled.emit()  # AcceptDialog has no cancel() method in 4.x
	assert_that(got).is_equal([["", true]])
	dlg.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- VibeAcpDock wiring

func test_dock_resolves_hash_only_permission_request_and_answers_jsonrpc() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()  # controls exist, but _ready()/auto-connect never runs
	# the agent announced the tool call before asking permission for it
	dock._render_update("sid", {"sessionUpdate": "tool_call", "toolCallId": "effect-abc123",
		"title": "run a tool", "kind": "execute", "rawInput": {"command": "ls -la"}})
	var responses: Array = []
	dock._on_permission_request({"toolCall": {"toolCallId": "effect-abc123"},
		"options": [{"optionId": "once", "name": "Allow once"}]},
		func(result: Variant, error: Variant = null) -> void: responses.append([result, error]))
	assert_that(dock._open_dialogs).has_size(1)
	var dlg: VibePermissionDialog = dock._open_dialogs[0]
	assert_that(dlg._summary.text).contains("Tool: run a tool")
	assert_that(dlg._summary.text).contains("Command: ls -la")
	dlg.get_ok_button().pressed.emit()
	assert_that(responses).is_equal([[{"outcome": {"outcome": "selected", "optionId": "once"}}, null]])
	assert_that(dock._open_dialogs).is_empty()
	dock.free()

func test_disconnect_answers_pending_permission_request_as_cancelled() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()  # no _ready(): no auto-connect
	var responses: Array = []
	dock._on_permission_request({"toolCall": {"toolCallId": "effect-q"},
		"options": [{"optionId": "once", "name": "Allow once"}]},
		func(result: Variant, error: Variant = null) -> void: responses.append([result, error]))
	assert_that(dock._open_dialogs).has_size(1)
	dock._handle_disconnect("agent process ended")
	# disconnect must answer the pending JSON-RPC request (cancelled) and clear the list
	assert_that(responses).is_equal([[{"outcome": {"outcome": "cancelled"}}, null]])
	assert_that(dock._open_dialogs).is_empty()
	dock.free()

func test_new_session_clears_tool_call_memory() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", {"sessionUpdate": "tool_call", "toolCallId": "effect-x", "title": "t"})
	assert_that(dock._tool_calls_by_id.has("effect-x")).is_true()
	dock._on_new_session()
	assert_that(dock._tool_calls_by_id).is_empty()
	dock.free()
