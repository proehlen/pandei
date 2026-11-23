class_name VibeAcpDock
extends VBoxContainer
## Bottom-panel dock that hosts the ACP conversation with vibe-acp.
## Owns the AcpClient lifecycle; the EditorPlugin only adds/removes this control.
##
## Transcript roles are colored/bolded via push_* (bbcode stays OFF so agent
## text containing '[' is rendered literally) and every line wraps
## (autowrap WORD_SMART), which matters on small laptop screens.
##
## Layout note: the editor clamps the vertical splitter between the editor
## area (+ bottom panel) and the full-height Inspector against the active
## bottom tab's combined minimum width. The header is therefore an
## HFlowContainer (min width = widest single control, not the row sum) and
## no header child carries a large fixed minimum width, so this dock never
## blocks the Inspector from being resized; the header simply wraps to more
## rows as the panel narrows. The same applies to the status bar below the
## input row, which is also an HFlowContainer for that reason.
##
## The header carries only interactive controls (buttons, dropdowns); all
## passive status text lives in the slim status bar beneath the prompt input
## (smaller font + slightly darkened background, so a short, distinct row):
## the git branch, connection/session state, turn state and token usage,
## separated by vertical bars.

var client: AcpClient = null
var fs: AcpFsHandler

var _project_root := ""
var _connect_btn: Button
var _disconnect_btn: Button
var _title_label: Label
var _status_label: Label
var _turn_label: Label
var _usage_label: Label
var _branch_label: Label
var _branch_sep: VSeparator  # = _status_seps[0]; kept as a named member for readability/tests
var _status_bar_bg: PanelContainer
var _status_bar: HFlowContainer
var _status_seps: Array[VSeparator] = []  # sep i sits between _status_labels_ordered[i] and [i+1]
var _status_labels_ordered: Array[Label] = []  # branch, status, turn, usage
var _branch_timer: Timer
var _status_font_size := 0
var _session_option: OptionButton
var _mode_option: OptionButton
var _transcript: RichTextLabel
var _input_row: HBoxContainer
var _input: TextEdit
var _send_btn: Button
var _stop_btn: Button
var _was_connected := false
var _busy := false
var _cancelling := false  # stop requested; busy until prompt_finished arrives
var _open_dialogs: Array = []  # pending permission/fs dialogs, cancelled on disconnect

# streaming block state: one open block per messageId, closed on role change
var _block_open := false
var _block_pushes := 0
var _open_msg_id := ""
var _open_role := ""

const COLOR_USER := Color(0.55, 0.80, 1.00)
const COLOR_AGENT := Color(0.90, 0.95, 1.00)
const COLOR_THOUGHT := Color(0.62, 0.62, 0.66)
const COLOR_TOOL := Color(0.95, 0.85, 0.45)
const COLOR_SYS := Color(0.62, 0.62, 0.66)
const COLOR_ERROR := Color(1.00, 0.50, 0.45)

func _ready() -> void:
	_project_root = ProjectSettings.globalize_path("res://")
	fs = AcpFsHandler.new(_project_root)
	custom_minimum_size = Vector2(0, 170)  # keep the panel usable when small
	_build_ui()
	# poll the branch name (a cheap .git/HEAD file read) so switching branches
	# in a terminal shows up here without an editor restart
	_branch_timer = Timer.new()
	_branch_timer.wait_time = 1.0
	_branch_timer.timeout.connect(_refresh_branch)
	add_child(_branch_timer)
	_refresh_branch()
	_branch_timer.start()
	_append_line_role(TranscriptRoles.ROLE_SYS, "Dock ready. " +
		("Connecting automatically…" if VibeAcpSettings.is_auto_connect() else "Press Connect to start the agent."))
	if VibeAcpSettings.is_auto_connect():
		connect_to_agent()

func shutdown() -> void:
	if client != null:
		client.connection.close()
		client = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()  # idempotent; also covers teardown paths that skip _exit_tree

# ---------------------------------------------------------------- UI setup

func _build_ui() -> void:
	# HFlowContainer, not HBoxContainer: a flow row's minimum width is the
	# widest child instead of the sum of all children, which keeps this dock's
	# combined minimum width small enough for the Inspector splitter to move.
	var header := HFlowContainer.new()
	add_child(header)

	_title_label = Label.new()
	_title_label.text = "Mistral Vibe"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_connect_btn = Button.new()
	_connect_btn.text = "Connect"
	_connect_btn.tooltip_text = "Start vibe-acp and connect"
	_connect_btn.pressed.connect(connect_to_agent)
	header.add_child(_connect_btn)

	_disconnect_btn = Button.new()
	_disconnect_btn.tooltip_text = "Disconnect (stops the vibe-acp process)"
	var close_icon: Texture2D = get_theme_icon("Close", "EditorIcons")
	if close_icon != null:
		_disconnect_btn.icon = close_icon
	else:
		_disconnect_btn.text = "Disconnect"
	_disconnect_btn.flat = true
	_disconnect_btn.visible = false
	_disconnect_btn.pressed.connect(disconnect_from_agent)
	header.add_child(_disconnect_btn)

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.tooltip_text = "Start a new session (fresh context)"
	new_btn.pressed.connect(_on_new_session)
	header.add_child(new_btn)
	var compact_btn := Button.new()
	compact_btn.text = "Compact"
	compact_btn.tooltip_text = "Ask the agent to compact the conversation (/compact)"
	compact_btn.pressed.connect(func() -> void: _send_text("/compact"))
	header.add_child(compact_btn)
	header.add_child(VSeparator.new())

	var s_lbl := Label.new()
	s_lbl.text = "Session:"
	header.add_child(s_lbl)
	_session_option = OptionButton.new()
	_session_option.custom_minimum_size.x = 120
	# without this the option's min width grows to the longest item text
	_session_option.fit_to_longest_item = false
	_session_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_session_option.tooltip_text = "Resume a previous ACP session"
	_session_option.item_selected.connect(func(i: int) -> void:
		if client != null and i >= 0 and i < _session_option.item_count:
			var sid := str(_session_option.get_item_metadata(i))
			if sid != "" and sid != client.session_id:
				client.load_or_new(sid))
	header.add_child(_session_option)
	var refresh_btn := Button.new()
	refresh_btn.tooltip_text = "Refresh session list"
	var reload_icon: Texture2D = get_theme_icon("Reload", "EditorIcons")
	if reload_icon != null:
		refresh_btn.icon = reload_icon
	else:
		refresh_btn.text = "Refresh"
	refresh_btn.flat = true
	refresh_btn.pressed.connect(func() -> void: if client != null: client.list_sessions())
	header.add_child(refresh_btn)

	var m_lbl := Label.new()
	m_lbl.text = "Mode:"
	header.add_child(m_lbl)
	_mode_option = OptionButton.new()
	_mode_option.custom_minimum_size.x = 110
	_mode_option.fit_to_longest_item = false
	_mode_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mode_option.tooltip_text = "Approval mode (session/set_mode)"
	_mode_option.item_selected.connect(func(i: int) -> void:
		if client != null and i >= 0 and i < _mode_option.item_count:
			var mode_id := str(_mode_option.get_item_metadata(i))
			VibeAcpSettings.set_mode(mode_id)
			client.set_mode(mode_id))
	header.add_child(_mode_option)

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = false  # agent text may contain '['; keep it literal
	_transcript.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # wrap long lines on small screens
	_transcript.scroll_following = true
	_transcript.selection_enabled = true
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.meta_clicked.connect(_on_transcript_meta_clicked)
	add_child(_transcript)

	_input_row = HBoxContainer.new()
	add_child(_input_row)
	_input = TextEdit.new()
	_input.custom_minimum_size = Vector2(0, 64)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Ask Vibe… (Ctrl+Enter to send)"
	_input.gui_input.connect(_on_input_gui_input)
	_input_row.add_child(_input)
	var btns := VBoxContainer.new()
	_input_row.add_child(btns)
	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.pressed.connect(_on_send)
	btns.add_child(_send_btn)
	_stop_btn = Button.new()
	_stop_btn.text = "Stop"
	_stop_btn.tooltip_text = "Cancel the running turn (session/cancel). Enabled only while a turn is active; stays busy until the agent confirms the turn ended."
	_stop_btn.pressed.connect(_on_stop)
	btns.add_child(_stop_btn)

	_build_status_bar()

## Slim status row beneath the prompt input: git branch + connection/session,
## turn and token-usage labels separated by vertical bars. A smaller font
## keeps the row short, a translucent dark PanelContainer background makes it
## read as its own strip instead of bleeding into the editor's bottom panel,
## and the inner HFlowContainer (not HBox) keeps the dock's minimum width at
## the widest single label so the Inspector splitter can still resize freely.
func _build_status_bar() -> void:
	_status_font_size = maxi(9, get_theme_default_font_size() - 3)
	_status_bar_bg = PanelContainer.new()
	_status_bar_bg.add_theme_stylebox_override("panel", _make_status_bar_stylebox())
	add_child(_status_bar_bg)
	_status_bar = HFlowContainer.new()
	_status_bar_bg.add_child(_status_bar)
	_branch_label = _make_status_label(180)
	_branch_label.tooltip_text = "Current git branch of this project (res://)"
	_status_bar.add_child(_branch_label)
	_branch_sep = _add_status_sep()
	_status_label = _make_status_label(120)
	_status_label.text = "disconnected"
	_status_bar.add_child(_status_label)
	var status_sep := _add_status_sep()
	_turn_label = _make_status_label(70)
	_status_bar.add_child(_turn_label)
	var turn_sep := _add_status_sep()
	_usage_label = _make_status_label(90)
	_status_bar.add_child(_usage_label)
	_status_labels_ordered = [_branch_label, _status_label, _turn_label, _usage_label]
	_status_seps = [_branch_sep, status_sep, turn_sep]

func _add_status_sep() -> VSeparator:
	var sep := VSeparator.new()
	_status_bar.add_child(sep)
	return sep

## Background of the status strip: a translucent black overlay, so the row is
## always one step darker than whatever the editor's bottom panel draws behind
## it — in dark and light editor themes alike. (Deriving a fixed color from a
## theme item does not work here: the editor theme defines no PanelContainer
## panel stylebox, so a themed lookup falls back to a light gray that renders
## LIGHTER than the dark panel.)
func _make_status_bar_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.25)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb

## Sync the status row with the label texts: labels without text are hidden (a
## flow container then gives them no space), and separator i shows only when
## its left section has text and SOME later section has text — so exactly one
## bar separates consecutive visible sections, never a dangling or doubled bar
## (e.g. with the turn section empty, session and usage still get one bar
## between them). Called every frame from _process; a few string checks.
func _sync_status_bar() -> void:
	for l in _status_labels_ordered:
		l.visible = not l.text.is_empty()
	for i in _status_seps.size():
		var left := _status_labels_ordered[i]
		var right_has_text := false
		for j in range(i + 1, _status_labels_ordered.size()):
			if not _status_labels_ordered[j].text.is_empty():
				right_has_text = true
				break
		_status_seps[i].visible = left.visible and right_has_text

## One status-bar label. The custom_minimum_size.x floor + EXPAND_FILL are
## required, not cosmetic: a flow container lays children out at their
## minimum width, and a Label with text_overrun_behavior set collapses its
## minimum width to ~0, so without the floor the text would be squeezed to
## ~1px and never render (only the separators would be visible). The floor
## also bounds the row's minimum width (flow min = widest child), and
## EXPAND_FILL lets the labels use leftover width when the panel is wide.
func _make_status_label(min_width: float) -> Label:
	var l := Label.new()
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.custom_minimum_size.x = min_width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", _status_font_size)
	if is_inside_tree():
		# dim the status text against the transcript; resolved through the
		# editor theme so it works in light and dark editor themes alike
		var c := get_theme_color("font_color", "Label")
		l.add_theme_color_override("font_color", Color(c.r, c.g, c.b, c.a * 0.65))
	return l

## Re-read the project's git branch into the status bar. Cheap file read, so
## the timer in _ready can call this every second.
func _refresh_branch() -> void:
	var branch := GitBranch.current_branch(_project_root)
	_branch_label.text = "git: " + branch if branch != "" else ""
	_sync_status_bar()

# ---------------------------------------------------------------- connection

func connect_to_agent() -> void:
	if client != null and client.is_open():
		return
	var exe := VibeAcpSettings.get_executable()
	if exe.is_empty():
		_append_line_role(TranscriptRoles.ROLE_ERROR, "vibe-acp executable not found. Install it (uv tool install mistral-vibe) " +
			"or set vibe_acp/executable in editor settings. Auth via CLI: vibe --setup")
		return
	var transport := PipeTransport.new()
	var err := transport.open_executable(exe, PackedStringArray())
	if err != OK:
		_append_line_role(TranscriptRoles.ROLE_ERROR, "failed to start %s (error %d)" % [exe, err])
		return
	var connection := AcpConnection.new(transport)
	client = AcpClient.new(connection, _project_root)
	_wire_client()
	_append_line_role(TranscriptRoles.ROLE_SYS, "started %s" % exe)
	client.initialize()

func disconnect_from_agent() -> void:
	if client != null:
		client.connection.close()
		client = null
	_handle_disconnect("stopped agent process")

## Central teardown for any disconnect (button, process death): answer pending
## server requests, reset turn state, refresh the header. Without this, a dead
## agent left _busy stuck and permission dialogs hanging forever.
func _handle_disconnect(message: String) -> void:
	for dlg in _open_dialogs:
		if is_instance_valid(dlg):
			dlg.cancel()  # AcceptDialog.cancel() -> canceled -> our handlers respond + free
	_open_dialogs.clear()
	_busy = false
	_cancelling = false
	_close_block()
	_turn_label.text = ""
	if message != "":
		_append_line_role(TranscriptRoles.ROLE_SYS, message)
	_update_connection_ui(false)

func _on_new_session() -> void:
	_transcript.clear()
	_close_block()
	_busy = false
	_cancelling = false
	_turn_label.text = ""
	# Only re-stored after the first prompt in the new session (see _send_text):
	# vibe-acp does not persist sessions that never received input.
	VibeAcpSettings.set_last_session("")
	VibeAcpSettings.set_last_session_busy(false)
	_update_send_state()
	if client != null and client.is_open():
		_append_line_role(TranscriptRoles.ROLE_SYS, "starting a new session…")
		client.new_session()
	else:
		_append_line_role(TranscriptRoles.ROLE_SYS, "not connected — press Connect first")

func _wire_client() -> void:
	client.initialized.connect(func(_result: Dictionary) -> void:
		_append_line_role(TranscriptRoles.ROLE_SYS, "ACP initialized, agent: %s v%s" % [
			str(client.server_info.get("agentInfo", {}).get("title", "vibe-acp")),
			str(client.server_info.get("agentInfo", {}).get("version", "?"))])
		_resume_stored_session())
	client.auth_methods_available.connect(func(_methods: Array) -> void:
		_append_line_role(TranscriptRoles.ROLE_SYS, "if prompts fail, sign in via CLI: vibe --setup"))
	client.session_ready.connect(_on_session_ready)
	client.session_error.connect(func(m: String) -> void: _append_line_role(TranscriptRoles.ROLE_ERROR, m))
	client.session_load_failed.connect(func(sid: String, _error: Variant) -> void:
		# the stored session is gone server-side; drop it so we don't retry it
		if VibeAcpSettings.get_last_session() == sid:
			VibeAcpSettings.set_last_session("")
			VibeAcpSettings.set_last_session_busy(false))
	client.sessions_listed.connect(_on_sessions_listed)
	client.prompt_finished.connect(_on_prompt_finished)
	client.session_update.connect(_render_update)
	client.log_line.connect(func(t: String) -> void: _append_line_role(TranscriptRoles.ROLE_SYS, t))

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

## Decide which session to open after (auto-)connect. Auto-resume of the
## stored session is off by default (vibe_acp/auto_resume): quitting the editor
## mid-turn used to make the agent silently pick up an abandoned task on the
## next start. When auto-resume is enabled, a session that was left mid-turn
## is still skipped. Either way the previous session stays available in the
## Session dropdown for a manual resume.
func _resume_stored_session() -> void:
	_decide_resume(VibeAcpSettings.get_last_session(),
		VibeAcpSettings.is_last_session_interrupted(),
		VibeAcpSettings.is_auto_resume())

## Pure-ish decision core, split out so tests can drive it with a fake client.
func _decide_resume(stored: String, interrupted: bool, auto_resume: bool) -> void:
	if client == null:
		return
	if VibeAcpSettings.should_auto_resume(stored, interrupted, auto_resume):
		client.load_or_new(stored)
		return
	if not stored.is_empty():
		var reason := "it was still working when the editor closed" if interrupted \
			else "auto-resume is off (vibe_acp/auto_resume, default off)"
		_append_line_role(TranscriptRoles.ROLE_SYS,
			"starting a new session — %s. Pick session %s in the Session dropdown to resume it manually." % [reason, stored.substr(0, 8)])
	client.new_session()

# ---------------------------------------------------------------- handlers

func _on_session_ready(sid: String, info: Dictionary) -> void:
	# NOTE: the stored "last session" is only overwritten once the user sends a
	# prompt (see _on_send). vibe-acp does not persist sessions that never got
	# any input, so storing them would make every restart log "Session not found".
	_status_label.text = "session " + sid.substr(0, 8)
	_append_line_role(TranscriptRoles.ROLE_SYS, "session ready: " + sid)
	_populate_modes(info.get("modes", {}))
	var stored := VibeAcpSettings.get_mode()
	if stored != "":
		for i in _mode_option.item_count:
			if str(_mode_option.get_item_metadata(i)) == stored:
				_mode_option.select(i)
				client.set_mode(stored)
				break
	client.list_sessions()  # populate the session dropdown automatically
	# session_id just became non-empty: re-evaluate the Send/Stop buttons
	# (they were disabled while the session was still being created/loaded)
	_update_send_state()

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
			if sid == client.session_id if client != null else false:
				_session_option.select(_session_option.item_count - 1)

func _on_prompt_finished(_sid: String, result: Variant, error: Variant) -> void:
	_busy = false
	_cancelling = false  # a pending stop is resolved once the turn actually ends
	_close_block()
	_turn_label.text = "idle"
	# the turn ended (finished, failed or cancelled) -> no longer interrupted
	if _sid == VibeAcpSettings.get_last_session():
		VibeAcpSettings.set_last_session_busy(false)
	if error != null:
		_append_line_role(TranscriptRoles.ROLE_ERROR, "prompt failed: " + str(error))
	# a normal end_turn is not transcript noise; it only flips the state label
	_update_send_state()

func _on_permission_request(params: Variant, respond: Callable) -> void:
	var p: Dictionary = params if params is Dictionary else {}
	var tool_call: Dictionary = p.get("toolCall", {}) if p.get("toolCall") is Dictionary else {}
	var options: Array = p.get("options", []) if p.get("options") is Array else []
	_append_line_role(TranscriptRoles.ROLE_SYS, "permission requested: " + str(tool_call.get("title", "run a tool")))
	var dlg := VibePermissionDialog.new()
	add_child(dlg)
	_open_dialogs.append(dlg)
	dlg.setup_dialog(tool_call, options)
	dlg.resolved.connect(func(option_id: String, cancelled: bool) -> void:
		_open_dialogs.erase(dlg)
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
	_open_dialogs.append(dlg)
	dlg.confirmed.connect(func() -> void:
		_open_dialogs.erase(dlg)
		var r := fs.handle_write(p)
		if r.has("error"):
			respond.call(null, r["error"])
		else:
			respond.call(r["result"])
		_append_line_role(TranscriptRoles.ROLE_SYS, "wrote " + path)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void:
		_open_dialogs.erase(dlg)
		respond.call(null, {"code": -32001, "message": "file write denied in the editor"})
		dlg.queue_free())
	dlg.popup_centered()

# ---------------------------------------------------------------- rendering

func _render_update(_sid: String, update: Dictionary) -> void:
	var role := TranscriptRoles.role_for_update(update)
	match role:
		TranscriptRoles.ROLE_AGENT, TranscriptRoles.ROLE_THOUGHT:
			_stream_chunk(role, update)
		TranscriptRoles.ROLE_USER:
			_append_line_role(TranscriptRoles.ROLE_USER, _content_text(update))
		TranscriptRoles.ROLE_TOOL:
			var is_call := str(update.get("sessionUpdate", "")) == "tool_call"
			var title := str(update.get("title", str(update.get("toolCallId", "?"))))
			var status := str(update.get("status", "pending" if is_call else ""))
			_append_tool_line(title, status, TranscriptRoles.locations_of(update))
		_:
			match str(update.get("sessionUpdate", "")):
				"usage_update":
					_usage_label.text = "%d/%d tok" % [int(update.get("used", 0)), int(update.get("size", 0))]
				"session_info_update":
					var t := str(update.get("title", ""))
					if t != "":
						_title_label.text = "Mistral Vibe — " + t
				"plan":
					for entry in update.get("entries", []):
						_append_line_role(TranscriptRoles.ROLE_TOOL, "plan [%s] %s" % [str(entry.get("status", "?")), str(entry.get("content", ""))])
				_:
					pass  # available_commands_update, config_option_update, etc.

func _stream_chunk(role: String, update: Dictionary) -> void:
	var mid := str(update.get("messageId", ""))
	if not _block_open or mid != _open_msg_id or _open_role != role:
		_open_block(role, TranscriptRoles.prefix_for_role(role))
		_open_msg_id = mid
		_open_role = role
	_transcript.append_text(_content_text(update))

func _content_text(update: Dictionary) -> String:
	var c: Variant = update.get("content", {})
	return str(c.get("text", "")) if c is Dictionary else ""

## Tool line with clickable file:line links (push_meta works with bbcode off).
func _append_tool_line(title: String, status: String, locations: Array) -> void:
	_close_block()
	_open_block(TranscriptRoles.ROLE_TOOL, TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_TOOL))
	_transcript.append_text("%s — %s" % [title, status])
	for loc in locations:
		if loc is Dictionary:
			var p := str(loc.get("path", ""))
			var line := int(loc.get("line", 0))
			if p != "":
				_transcript.append_text("  ")
				_transcript.push_meta({"path": p, "line": line})
				_transcript.push_color(COLOR_USER)
				_transcript.push_underline()
				_transcript.append_text(_display_path(p) + (":%d" % line if line > 0 else ""))
				_transcript.pop()  # underline
				_transcript.pop()  # color
				_transcript.pop()  # meta
	_close_block()

func _display_path(p: String) -> String:
	return p if p.begins_with("res://") else ProjectSettings.localize_path(p)

func _on_transcript_meta_clicked(meta: Variant) -> void:
	if not (meta is Dictionary):
		return
	var p := str(meta.get("path", ""))
	var line := int(meta.get("line", 0))
	if p.is_empty():
		return
	var res := _display_path(p)
	if res.ends_with(".gd") and ResourceLoader.exists(res):
		var s := load(res) as Script
		if s != null:
			EditorInterface.edit_script(s, maxi(line, 1))
	elif res.ends_with(".tscn") and ResourceLoader.exists(res):
		EditorInterface.open_scene_from_path(res)
	elif ResourceLoader.exists(res):
		EditorInterface.edit_resource(load(res))

func _role_color(role: String) -> Color:
	match role:
		TranscriptRoles.ROLE_USER:
			return COLOR_USER
		TranscriptRoles.ROLE_AGENT:
			return COLOR_AGENT
		TranscriptRoles.ROLE_THOUGHT:
			return COLOR_THOUGHT
		TranscriptRoles.ROLE_TOOL:
			return COLOR_TOOL
		TranscriptRoles.ROLE_ERROR:
			return COLOR_ERROR
	return COLOR_SYS

func _open_block(role: String, prefix: String) -> void:
	_close_block()
	_transcript.push_color(_role_color(role))
	_transcript.push_bold()
	_transcript.append_text(prefix)
	_transcript.pop()  # bold off; color stays active for the body text
	_block_pushes = 1
	if role == TranscriptRoles.ROLE_THOUGHT:
		_transcript.push_italics()  # Godot 4 name; push_italic() does not exist
		_block_pushes += 1
	_block_open = true

func _close_block() -> void:
	if _block_open:
		_transcript.append_text("\n")
		for i in _block_pushes:
			_transcript.pop()
	_block_open = false
	_block_pushes = 0
	_open_msg_id = ""
	_open_role = ""

func _append_line_role(role: String, s: String) -> void:
	_close_block()
	_open_block(role, TranscriptRoles.prefix_for_role(role))
	_transcript.append_text(s)
	_close_block()

# ---------------------------------------------------------------- input

func _on_send() -> void:
	_send_text(_input.text)

## Single source of truth for "would sending do anything right now?".
## Both the Send button and the Ctrl+Enter handler use this, so the button
## is enabled exactly when Ctrl+Enter works — and disabled exactly when
## Ctrl+Enter would no-op (e.g. no session yet: prompt() would silently drop
## the text, so we must not clear the input or flip _busy in that window).
func _can_send() -> bool:
	return client != null and client.is_open() and not _busy and not client.session_id.is_empty()

## Stop is only effective while a turn is in flight, and only once per turn:
## session/cancel is a notification (no response), the turn actually ends
## when prompt_finished arrives — until then the button stays busy.
func _can_stop() -> bool:
	return client != null and _busy and not _cancelling

func _on_stop() -> void:
	if not _can_stop():
		return
	_cancelling = true
	_turn_label.text = "stopping…"
	_append_line_role(TranscriptRoles.ROLE_SYS, "stop requested — waiting for the agent to end the turn")
	client.cancel()
	_update_send_state()

func _send_text(text: String) -> void:
	if not _can_send():
		return
	if text.strip_edges().is_empty():
		return
	_input.text = ""
	_busy = true
	_turn_label.text = "working…"
	_update_send_state()
	client.prompt(text)
	# Only now does this session become the stored one: sessions with no input
	# are not persisted by vibe-acp. The busy flag marks it as mid-turn until
	# prompt_finished arrives; if the editor is quit in between, the flag
	# survives the restart and the session counts as interrupted.
	VibeAcpSettings.set_last_session(client.session_id)
	VibeAcpSettings.set_last_session_busy(true)

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
			_on_send()
			get_viewport().set_input_as_handled()

func _update_send_state() -> void:
	_send_btn.disabled = not _can_send()
	_stop_btn.disabled = not _can_stop()
	_stop_btn.text = "Stopping…" if _cancelling else "Stop"

func _update_connection_ui(open: bool) -> void:
	_connect_btn.visible = not open
	_disconnect_btn.visible = open
	_status_label.text = "connected" if open else "disconnected"
	if not open:
		_turn_label.text = ""
		_usage_label.text = ""
	_update_send_state()

func _process(_delta: float) -> void:
	if client != null:
		client.pump()
		var open := client.is_open()
		if open != _was_connected:
			_was_connected = open
			if not open:
				_handle_disconnect("agent process ended (exit %d)" % client.connection.exit_code())
				client = null
			else:
				_update_connection_ui(true)
	# cheap safety net: keep Send/Stop in sync with the predicates every frame
	# so no state change (e.g. session_id arriving) can leave them stale
	_update_send_state()
	# likewise keep the status-bar labels/separators in sync with their texts
	_sync_status_bar()
