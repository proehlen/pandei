extends GdUnitTestSuite
## Session dropdown selection contract: the selected entry must always mirror
## client.session_id — the matching item when the current session is in the
## session/list result, and BLANK (select(-1)) while it is not (a fresh session
## is not persisted by vibe-acp until its first prompt, so right after editor
## start or the New button the list does not contain the current session).
## add_item() auto-selects the first (latest) item after clear(), which
## _on_sessions_listed() must override; picking any entry still resumes it via
## session/load. Both the editor-start path and the New-button path funnel
## through _on_sessions_listed().
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


## Exactly what PopupMenu::activate_item() emits on a mouse click.
func _click(f: Dictionary, index: int) -> void:
	f["dock"]._session_option.get_popup().emit_signal("index_pressed", index)


func _load_requests(t: FakeTransport) -> Array:
	return t.written.filter(func(m: Dictionary) -> bool: return m.get("method", "") == "session/load")


func after_test() -> void:
	# _on_new_session()/_send_text persist session state in editor settings; don't leak
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)


## Fresh session active (its id is not in session/list yet): the dropdown must
## be BLANK, not pre-select the latest entry, and picking the latest must resume it.
func test_new_session_leaves_dropdown_blank_and_picking_latest_resumes_it() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-new-999"  # current session, not in the list
	f["dock"]._on_sessions_listed(_sessions())
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.selected).is_equal(-1)  # blank, NOT the latest session
	assert_that(opt.get_selected_metadata()).is_null()
	_click(f, 0)  # pick the latest session from the blank state
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)


## Same after the New button: _on_new_session() + session_ready lead to
## _on_sessions_listed() with the new id absent from the list — selection stays
## blank and the latest session remains one click away.
func test_new_session_button_path_leaves_dropdown_blank() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-old-000"
	f["dock"]._on_sessions_listed(_sessions())
	f["dock"]._on_new_session()  # sends session/new
	assert_that(f["transport"].written.any(func(m: Dictionary) -> bool: return m.get("method", "") == "session/new")).is_true()
	# server answers session/new, then session/list (triggered by _on_session_ready)
	f["client"].session_id = "sid-new-999"
	f["dock"]._on_session_ready("sid-new-999", {})
	f["dock"]._on_sessions_listed(_sessions())  # session/list response; new id not persisted yet
	assert_that(f["dock"]._session_option.selected).is_equal(-1)
	_click(f, 0)
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)


## Current session IS in the list: it must be the selected entry (not the latest).
## Re-clicking it is a no-op (already in it); picking another entry loads it.
func test_current_session_in_list_is_selected() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-older-222"
	f["dock"]._on_sessions_listed(_sessions())
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.selected).is_equal(1)  # the current session, not item 0 (latest)
	assert_that(str(opt.get_item_metadata(opt.selected))).is_equal("sid-older-222")
	_click(f, 1)  # re-click current session: must NOT session/load it again
	assert_that(_load_requests(f["transport"])).is_empty()
	_click(f, 0)  # pick the latest instead
	var loads := _load_requests(f["transport"])
	assert_that(loads).has_size(1)
	assert_that(loads[0]["params"]["sessionId"]).is_equal("sid-latest-111")
	_free_dock(f)


## Once the current session becomes persisted (first prompt sent) and shows up in
## a refreshed list, the selection must move to it.
func test_selection_follows_current_session_after_refresh() -> void:
	var f := _make_dock()
	f["client"].session_id = "sid-new-999"
	f["dock"]._on_sessions_listed(_sessions())
	assert_that(f["dock"]._session_option.selected).is_equal(-1)
	# the new session got its first prompt -> persisted -> now listed, newest first
	f["client"].session_id = "sid-new-999"
	var with_new: Array = [{"sessionId": "sid-new-999", "title": "current"}] + _sessions()
	f["dock"]._on_sessions_listed(with_new)
	var opt: OptionButton = f["dock"]._session_option
	assert_that(opt.selected).is_equal(0)
	assert_that(str(opt.get_item_metadata(opt.selected))).is_equal("sid-new-999")
	_free_dock(f)


## No client / empty list: nothing may be selected either.
func test_blank_when_no_client_or_empty_list() -> void:
	var f := _make_dock()
	f["dock"].client = null
	f["dock"]._on_sessions_listed(_sessions())
	assert_that(f["dock"]._session_option.selected).is_equal(-1)
	f["dock"].client = f["client"]
	f["client"].session_id = "sid-x"
	f["dock"]._on_sessions_listed([])
	assert_that(f["dock"]._session_option.selected).is_equal(-1)
	_free_dock(f)
