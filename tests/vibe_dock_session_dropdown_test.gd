extends GdUnitTestSuite
## Session dropdown re-selection (bug fix): after clear() the OptionButton's
## add_item() auto-selects the first (latest) session, and by default
## OptionButton._select() swallows a re-click on the already-selected item
## (early return unless allow_reselect is set). While a NEW session is active
## — after editor start as well as after the New button, both funnel through
## _on_sessions_listed() — the preselected latest session must still be
## pickable; the old workaround was selecting an earlier session first and
## then the latest one.
##
## Drives the dock with a fake transport. Only the session OptionButton is put
## into the tree (OptionButton emits item_selected only when inside the tree),
## so the dock's _ready()/auto-connect never spawns a real vibe-acp.

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
	# reparent the dropdown into the test tree so OptionButton._select() emits
	# item_selected (it only emits while inside the tree)
	dock._session_option.get_parent().remove_child(dock._session_option)
	add_child(dock._session_option)
	var t := FakeTransport.new()
	var client := AcpClient.new(AcpConnection.new(t), "/tmp/fake-project")
	dock.client = client
	return {"dock": dock, "transport": t, "client": client}


func _free_dock(f: Dictionary) -> void:
	var dock: VibeAcpDock = f["dock"]
	remove_child(dock._session_option)
	dock._session_option.free()
	dock.free()


## Newest-first, as vibe-acp returns them.
func _sessions() -> Array:
	return [
		{"sessionId": "sid-latest-111", "title": "latest"},
		{"sessionId": "sid-older-222", "title": "older"},
		{"sessionId": "sid-oldest-333"},
	]


## Exactly what PopupMenu::activate_item() emits on a mouse click — for every
## enabled item, including the already-checked radio one.
func _click(f: Dictionary, index: int) -> void:
	f["dock"]._session_option.get_popup().emit_signal("index_pressed", index)


func _load_requests(t: FakeTransport) -> Array:
	return t.written.filter(func(m: Dictionary) -> bool: return m.get("method", "") == "session/load")


func after_test() -> void:
	# _on_new_session()/_send_text persist session state in editor settings; don't leak
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)


## The reported bug: fresh session active (its id is not in session/list yet,
## vibe-acp does not persist input-less sessions), the dropdown pre-selects the
## latest session, and re-clicking that preselected item must resume it.
func test_new_session_preselects_latest_and_reclick_resumes_it() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-new-999"  # current session, not in the list
	f["dock"]._on_sessions_listed(_sessions())
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.allow_reselect).is_true()
	assert_that(opt.selected).is_equal(0)  # latest session preselected
	_click(f, 0)  # re-click the already-selected item
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)


## Same path after the New button: _on_new_session() + session_ready lead to
## _on_sessions_listed() with the new id absent from the list — the preselected
## latest session must still be one click away.
func test_new_session_button_path_still_allows_picking_latest() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-old-000"
	f["dock"]._on_sessions_listed(_sessions())
	f["dock"]._on_new_session()  # sends session/new
	assert_that(f["transport"].written.any(func(m: Dictionary) -> bool: return m.get("method", "") == "session/new")).is_true()
	# server answers session/new, then session/list (triggered by _on_session_ready)
	f["client"].session_id = "sid-new-999"
	f["dock"]._on_session_ready("sid-new-999", {})
	f["dock"]._on_sessions_listed(_sessions())  # session/list response; new id not persisted yet
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.selected).is_equal(0)
	_click(f, 0)
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)


## When the current session IS in the list it is the preselected item; re-clicking
## it must be a no-op (we are already in it), while picking any other entry loads it.
func test_current_session_preselected_reclick_is_noop_other_items_load() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-older-222"
	f["dock"]._on_sessions_listed(_sessions())
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.selected).is_equal(1)  # the current session is preselected
	_click(f, 1)  # re-click current session: must NOT session/load it again
	assert_that(_load_requests(f["transport"])).is_empty()
	_click(f, 0)  # pick the latest instead
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)
