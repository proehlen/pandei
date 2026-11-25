extends GdUnitTestSuite
## Active-model display in the status bar. ACP 3.x carries no "models" field on
## session/new|load; vibe exposes the model as the "model" session config option
## (configOptions in the session response, re-sent as config_option_update when
## it changes, e.g. via /model). The dock shows its display name in its own
## status-bar section. Drives the dock with a fake transport; the UI is built
## without entering the tree so _ready() never spawns a real vibe-acp.

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
	dock._build_ui()
	var t := FakeTransport.new()
	var client := AcpClient.new(AcpConnection.new(t), "/tmp/fake-project")
	dock.client = client
	dock._wire_client()
	return {"dock": dock, "transport": t, "client": client}


func _model_config(current: String, display: String) -> Array:
	return [{
		"id": "model", "name": "Model", "type": "select", "currentValue": current,
		"options": [{"value": current, "name": display}],
	}, {
		"id": "thinking", "name": "Thinking", "type": "select", "currentValue": "medium",
		"options": [],
	}]


func after_test() -> void:
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)


func test_model_name_from_config_options_prefers_display_name() -> void:
	assert_that(VibeAcpDock._model_name_from_config_options(_model_config("devstral-small", "Devstral Small"))).is_equal("Devstral Small")


func test_model_name_from_config_options_falls_back_to_raw_id() -> void:
	# no options list / no matching name: show the raw alias
	assert_that(VibeAcpDock._model_name_from_config_options([{"id": "model", "currentValue": "devstral-small", "options": []}])).is_equal("devstral-small")
	# no model option at all (e.g. older agent)
	assert_that(VibeAcpDock._model_name_from_config_options([{"id": "thinking", "currentValue": "medium"}])).is_equal("")
	assert_that(VibeAcpDock._model_name_from_config_options("nonsense")).is_equal("")


func test_session_ready_shows_model_in_status_bar() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	f["client"].session_id = "sid-abc123"
	dock._on_session_ready("sid-abc123", {"configOptions": _model_config("devstral-small", "Devstral Small")})
	assert_that(dock._model_label.text).is_equal("Devstral Small")
	f["dock"].free()


func test_session_ready_without_config_options_leaves_model_empty() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	f["client"].session_id = "sid-abc123"
	dock._on_session_ready("sid-abc123", {})
	assert_that(dock._model_label.text).is_empty()
	f["dock"].free()


func test_config_option_update_switches_displayed_model() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	f["client"].session_id = "sid-abc123"
	dock._on_session_ready("sid-abc123", {"configOptions": _model_config("devstral-small", "Devstral Small")})
	# the agent re-sends config_option_update after a /model switch
	dock._render_update("sid-abc123", {"sessionUpdate": "config_option_update",
		"configOptions": _model_config("magistral", "Magistral")})
	assert_that(dock._model_label.text).is_equal("Magistral")
	f["dock"].free()


func test_disconnect_clears_model_label() -> void:
	var f := _make_dock()
	var dock: VibeAcpDock = f["dock"]
	f["client"].session_id = "sid-abc123"
	dock._on_session_ready("sid-abc123", {"configOptions": _model_config("devstral-small", "Devstral Small")})
	f["transport"].close()
	dock._handle_disconnect("agent process ended")
	assert_that(dock._model_label.text).is_empty()
	assert_that(dock._model_name).is_empty()
	f["dock"].free()
