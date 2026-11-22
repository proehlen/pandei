class_name VibeAcpDock
extends VBoxContainer
## Bottom-panel dock that hosts the ACP conversation with vibe-acp.
## Owns the AcpClient lifecycle; the EditorPlugin only adds/removes this control.

var client: AcpClient = null
var fs: AcpFsHandler

var _project_root := ""
var _connect_btn: Button
var _title_label: Label
var _status_label: Label
var _usage_label: Label
var _session_option: OptionButton
var _mode_option: OptionButton
var _transcript: RichTextLabel
var _input: TextEdit
var _send_btn: Button
var _was_connected := false
var _busy := false
var _last_msg_id := ""

func _ready() -> void:
	_project_root = ProjectSettings.globalize_path("res://")
	fs = AcpFsHandler.new(_project_root)
	_build_ui()
	_append_line("[vibe-acp] Dock ready. Press Connect to start the agent.")
	if VibeAcpSettings.is_auto_connect():
		connect_to_agent()

func shutdown() -> void:
	if client != null:
		client.connection.close()
		client = null

# ---------------------------------------------------------------- UI setup

func _build_ui() -> void:
	var header := HBoxContainer.new()
	add_child(header)

	_title_label = Label.new()
	_title_label.text = "Mistral Vibe"
	header.add_child(_title_label)

	_connect_btn = Button.new()
	_connect_btn.text = "Connect"
	_connect_btn.toggle_mode = true
	_connect_btn.toggled.connect(_on_connect_toggled)
	header.add_child(_connect_btn)
	header.add_child(VSeparator.new())

	var s_lbl := Label.new()
	s_lbl.text = "Session:"
	header.add_child(s_lbl)
	_session_option = OptionButton.new()
	_session_option.custom_minimum_size.x = 150
	_session_option.tooltip_text = "Resume a previous ACP session"
	_session_option.item_selected.connect(func(i: int) -> void:
		if client != null and i >= 0 and i < _session_option.item_count:
			var sid := str(_session_option.get_item_metadata(i))
			if sid != "" and sid != client.session_id:
				client.load_or_new(sid))
	header.add_child(_session_option)
	var list_btn := Button.new()
	list_btn.text = "List"
	list_btn.tooltip_text = "List resumable sessions (session/list)"
	list_btn.pressed.connect(func() -> void: if client != null: client.list_sessions())
	header.add_child(list_btn)

	var m_lbl := Label.new()
	m_lbl.text = "Mode:"
	header.add_child(m_lbl)
	_mode_option = OptionButton.new()
	_mode_option.custom_minimum_size.x = 130
	_mode_option.tooltip_text = "Approval mode (session/set_mode)"
	_mode_option.item_selected.connect(func(i: int) -> void:
		if client != null and i >= 0 and i < _mode_option.item_count:
			var mode_id := str(_mode_option.get_item_metadata(i))
			VibeAcpSettings.set_mode(mode_id)
			client.set_mode(mode_id))
	header.add_child(_mode_option)
	header.add_child(VSeparator.new())

	_status_label = Label.new()
	_status_label.text = "disconnected"
	header.add_child(_status_label)
	_usage_label = Label.new()
	_usage_label.text = ""
	header.add_child(_usage_label)

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = false  # agent text may contain '['; keep it literal
	_transcript.scroll_following = true
	_transcript.selection_enabled = true
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_transcript)

	var input_row := HBoxContainer.new()
	add_child(input_row)
	_input = TextEdit.new()
	_input.custom_minimum_size = Vector2(0, 64)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Ask Vibe… (Ctrl+Enter to send)"
	_input.gui_input.connect(_on_input_gui_input)
	input_row.add_child(_input)
	var btns := VBoxContainer.new()
	input_row.add_child(btns)
	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.pressed.connect(_on_send)
	btns.add_child(_send_btn)
	var stop_btn := Button.new()
	stop_btn.text = "Stop"
	stop_btn.pressed.connect(func() -> void: if client != null: client.cancel())
	btns.add_child(stop_btn)

# ---------------------------------------------------------------- connection

func connect_to_agent() -> void:
	if client != null and client.is_open():
		return
	var exe := VibeAcpSettings.get_executable()
	if exe.is_empty():
		_append_line("[err] vibe-acp executable not found. Install it (uv tool install mistral-vibe) " +
			"or set vibe_acp/executable in editor settings. Auth via CLI: vibe --setup")
		_connect_btn.set_pressed_no_signal(false)
		return
	var transport := PipeTransport.new()
	var err := transport.open_executable(exe, PackedStringArray())
	if err != OK:
		_append_line("[err] failed to start %s (error %d)" % [exe, err])
		_connect_btn.set_pressed_no_signal(false)
		return
	var connection := AcpConnection.new(transport)
	client = AcpClient.new(connection, _project_root)
	_wire_client()
	_append_line("[sys] started %s" % exe)
	client.initialize()

func disconnect_from_agent() -> void:
	if client != null:
		client.connection.close()
		_append_line("[sys] stopped agent process")
		client = null
	_connect_btn.set_pressed_no_signal(false)
	_status_label.text = "disconnected"

func _on_connect_toggled(pressed: bool) -> void:
	if pressed:
		connect_to_agent()
	else:
		disconnect_from_agent()

func _wire_client() -> void:
	client.initialized.connect(func(_result: Dictionary) -> void:
		_append_line("[sys] ACP initialized (protocol v%d), agent: %s v%s" % [
			AcpClient.PROTOCOL_VERSION,
			str(client.server_info.get("agentInfo", {}).get("title", "vibe-acp")),
			str(client.server_info.get("agentInfo", {}).get("version", "?"))])
		client.load_or_new(VibeAcpSettings.get_last_session()))
	client.auth_methods_available.connect(func(_methods: Array) -> void:
		_append_line("[sys] agent reports auth methods; if prompts fail, sign in via CLI: vibe --setup"))
	client.session_ready.connect(_on_session_ready)
	client.session_error.connect(func(m: String) -> void: _append_line("[err] " + m))
	client.sessions_listed.connect(_on_sessions_listed)
	client.prompt_finished.connect(_on_prompt_finished)
	client.session_update.connect(_render_update)
	client.log_line.connect(func(t: String) -> void: _append_line("[agent] " + t))

	client.dispatcher.register_request_handler("session/request_permission", _on_permission_request)
	client.dispatcher.register_request_handler("fs/read_text_file", func(params: Variant, respond: Callable) -> void:
		var r := fs.handle_read(params if params is Dictionary else {})
		if r.has("error"):
			respond.call(null, r["error"])
		else:
			respond.call(r["result"]))
	client.dispatcher.register_request_handler("fs/write_text_file", _on_fs_write)
	for m in ["terminal/create", "terminal/output", "terminal/release", "terminal/wait_for_exit", "terminal/kill"]:
		client.dispatcher.register_request_handler(m, func(_params: Variant, respond: Callable) -> void:
			respond.call(null, {"code": -32601,
				"message": "Godot client provides no terminal; the agent should use its own shell tools."}))

# ---------------------------------------------------------------- handlers

func _on_session_ready(sid: String, info: Dictionary) -> void:
	VibeAcpSettings.set_last_session(sid)
	_status_label.text = "session " + sid.substr(0, 8)
	_append_line("[sys] session ready: %s" % sid)
	_populate_modes(info.get("modes", {}))
	var stored := VibeAcpSettings.get_mode()
	if stored != "":
		for i in _mode_option.item_count:
			if str(_mode_option.get_item_metadata(i)) == stored:
				_mode_option.select(i)
				client.set_mode(stored)
				break

func _populate_modes(modes: Variant) -> void:
	_mode_option.clear()
	if modes is Dictionary and modes.has("availableModes"):
		for m in modes["availableModes"]:
			_mode_option.add_item(str(m.get("name", m.get("id", "?"))))
			_mode_option.set_item_metadata(_mode_option.item_count - 1, str(m.get("id", "")))
		if modes.has("currentModeId"):
			var cur := str(modes["currentModeId"])
			for i in _mode_option.item_count:
				if str(_mode_option.get_item_metadata(i)) == cur:
					_mode_option.select(i)
					break

func _on_sessions_listed(sessions: Array) -> void:
	_session_option.clear()
	for s in sessions:
		if s is Dictionary:
			var sid := str(s.get("sessionId", ""))
			var label := sid.substr(0, 8)
			if s.has("title") and str(s["title"]) != "":
				label += " — " + str(s["title"])
			_session_option.add_item(label)
			_session_option.set_item_metadata(_session_option.item_count - 1, sid)

func _on_prompt_finished(_sid: String, result: Variant, error: Variant) -> void:
	_busy = false
	_update_send_state()
	if error != null:
		_append_line("[err] prompt failed: " + str(error))
	elif result is Dictionary:
		_append_line("[sys] turn finished: %s" % str(result.get("stopReason", "?")))

func _on_permission_request(params: Variant, respond: Callable) -> void:
	var p: Dictionary = params if params is Dictionary else {}
	var tool_call: Dictionary = p.get("toolCall", {}) if p.get("toolCall") is Dictionary else {}
	var options: Array = p.get("options", []) if p.get("options") is Array else []
	_append_line("[perm] %s wants permission" % str(tool_call.get("title", "run a tool")))
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	dlg.setup_dialog(tool_call, options)
	dlg.resolved.connect(func(option_id: String, cancelled: bool) -> void:
		if cancelled:
			respond.call({"outcome": {"outcome": "cancelled"}})
		else:
			respond.call({"outcome": {"outcome": "selected", "optionId": option_id}})
		dlg.queue_free())
	dlg.popup_centered()

func _on_fs_write(params: Variant, respond: Callable) -> void:
	var p: Dictionary = params if params is Dictionary else {}
	var path := str(p.get("path", ""))
	var dlg := ConfirmationDialog.new()
	dlg.title = "Vibe wants to write a file"
	dlg.dialog_text = "Allow vibe-acp to write:\n%s\n\n(%d bytes)" % [path, str(p.get("content", "")).length()]
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		var r := fs.handle_write(p)
		if r.has("error"):
			respond.call(null, r["error"])
		else:
			respond.call(r["result"])
		_append_line("[fs] wrote " + path)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void:
		respond.call(null, {"code": -32001, "message": "file write denied in the editor"})
		dlg.queue_free())
	dlg.popup_centered()

# ---------------------------------------------------------------- rendering

func _render_update(_sid: String, update: Dictionary) -> void:
	var kind := str(update.get("sessionUpdate", ""))
	match kind:
		"agent_message_chunk":
			var mid := str(update.get("messageId", ""))
			if mid != _last_msg_id:
				_last_msg_id = mid
				_transcript.append_text("\nVibe: ")
			_transcript.append_text(str(_content_text(update)))
		"agent_thought_chunk":
			_transcript.append_text(str(_content_text(update)))
		"user_message_chunk":
			_last_msg_id = ""
			_append_line("\nYou: " + _content_text(update))
		"tool_call":
			_append_line("\n[tool] %s — %s" % [str(update.get("title", "?")), str(update.get("status", "pending"))])
		"tool_call_update":
			_append_line("       %s: %s" % [str(update.get("title", str(update.get("toolCallId", "")))), str(update.get("status", ""))])
		"usage_update":
			_usage_label.text = "%d/%d tok" % [int(update.get("used", 0)), int(update.get("size", 0))]
		"session_info_update":
			var t := str(update.get("title", ""))
			if t != "":
				_title_label.text = "Mistral Vibe — " + t
		"plan":
			for entry in update.get("entries", []):
				_append_line("  plan [%s] %s" % [str(entry.get("status", "?")), str(entry.get("content", ""))])
		_:
			pass  # available_commands_update, config_option_update, etc.

func _content_text(update: Dictionary) -> String:
	var c: Variant = update.get("content", {})
	return str(c.get("text", "")) if c is Dictionary else ""

func _append_line(s: String) -> void:
	_transcript.append_text(s + "\n")

# ---------------------------------------------------------------- input

func _on_send() -> void:
	if client == null or not client.is_open() or _busy:
		return
	var text := _input.text
	_input.text = ""
	_busy = true
	_update_send_state()
	client.prompt(text)

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
			_on_send()
			get_viewport().set_input_as_handled()

func _update_send_state() -> void:
	_send_btn.disabled = client == null or not client.is_open() or _busy or client.session_id.is_empty()

func _process(_delta: float) -> void:
	if client != null:
		client.pump()
		var open := client.is_open()
		if open != _was_connected:
			_was_connected = open
			_connect_btn.set_pressed_no_signal(open)
			_status_label.text = "connected" if open else "disconnected (exit %d)" % client.connection.exit_code()
			if not open:
				_append_line("[sys] agent process ended")
		_update_send_state()
