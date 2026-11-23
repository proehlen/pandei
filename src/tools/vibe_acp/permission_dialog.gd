class_name VibePermissionDialog
extends AcceptDialog
## Modal approval dialog for ACP session/request_permission.
## Emits resolved(option_id, cancelled) exactly once; the caller then answers
## the JSON-RPC request and frees the dialog.
##
## Sizing contract (the dialog used to grow taller than the screen, hiding the
## OK button behind the bottom edge): all text lives in bounded ScrollContainers
## — an autowrap Label reports its full wrapped height as minimum size, so text
## must sit inside a ScrollContainer, which does not propagate content min size —
## and the window's max_size is clamped to the screen. popup_on_screen() clamps
## size and position, so the dialog is always fully visible.
##
## Readability contract: session/request_permission often carries only a
## toolCallId hash; setup_dialog() accepts the tool_call updates the dock saw
## earlier (known_by_id) so the always-visible summary names the actual tool
## being approved. The raw JSON payload sits behind a collapsed "Debug info"
## section (hidden by default) for when the summary is not self-explanatory.

signal resolved(option_id: String, cancelled: bool)

const DIALOG_MIN_SIZE := Vector2i(500, 0)
const SUMMARY_AREA_MIN_SIZE := Vector2(480, 96)  # always-visible summary
const DEBUG_AREA_MIN_SIZE := Vector2(480, 150)   # raw payload, hidden by default

var _summary: Label
var _debug_toggle: Button
var _debug_scroll: ScrollContainer
var _raw: Label
var _option_button: OptionButton
var _done := false

func _init() -> void:
	title = "Vibe requests permission"
	min_size = DIALOG_MIN_SIZE
	var vb := VBoxContainer.new()
	vb.add_child(_spacer(2))
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_bounded_scroll(_summary, SUMMARY_AREA_MIN_SIZE))
	vb.add_child(_spacer(2))
	# collapsed "Debug info" disclosure: a flat toggle button (DisclosureTriangle
	# is editor-only, not available at runtime) with an arrow icon when the
	# editor theme provides one
	_debug_toggle = Button.new()
	_debug_toggle.text = "Debug info"
	_debug_toggle.flat = true
	_debug_toggle.toggle_mode = true
	_debug_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_toggle.focus_mode = Control.FOCUS_NONE
	var arrow: Texture2D = get_theme_icon("ArrowRight", "EditorIcons")
	if arrow != null:
		_debug_toggle.icon = arrow
	_debug_toggle.toggled.connect(_on_debug_toggled)
	vb.add_child(_debug_toggle)
	_raw = Label.new()
	_raw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_raw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_scroll = _bounded_scroll(_raw, DEBUG_AREA_MIN_SIZE)
	_debug_scroll.visible = false  # hidden by default; expand for the raw payload
	vb.add_child(_debug_scroll)
	vb.add_child(_spacer(6))
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Decision:"
	row.add_child(lbl)
	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_option_button)
	vb.add_child(row)
	add_child(vb)
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)

## ScrollContainer that bounds its content: wraps text instead of h-scrolling
## and never lets the content inflate the dialog's minimum height.
func _bounded_scroll(content: Control, min_size: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = min_size
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	return scroll

func _on_debug_toggled(pressed: bool) -> void:
	_debug_scroll.visible = pressed
	var arrow: Texture2D = get_theme_icon("ArrowDown" if pressed else "ArrowRight", "EditorIcons")
	if arrow != null:
		_debug_toggle.icon = arrow
	_refit()  # grow/shrink the window to the new content, still fully on screen

func _ready() -> void:
	max_size = _screen_size()

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func setup_dialog(tool_call: Dictionary, options: Array, known_by_id: Dictionary = {}) -> void:
	_summary.text = PermissionText.summarize(tool_call, known_by_id)
	_raw.text = PermissionText.raw_json(tool_call, known_by_id)
	_option_button.clear()
	for i in options.size():
		var o: Dictionary = options[i]
		_option_button.add_item(str(o.get("name", o.get("optionId", "Allow"))))
		_option_button.set_item_metadata(i, str(o.get("optionId", "")))
	if options.size() > 0:
		_option_button.select(0)

## popup_centered() plus clamping into the screen: the OK button must always be
## reachable without resizing/dragging the window first.
func popup_on_screen() -> void:
	if not is_inside_tree():
		return  # callers add the dialog to the tree before popping it up
	popup_centered()
	_refit()

## Fit the window to its (bounded) content and clamp it into the screen.
func _refit() -> void:
	if not is_inside_tree():
		return
	var screen := _screen_size()
	max_size = screen
	size = Vector2i(get_contents_minimum_size()).min(screen).max(min_size)
	var max_pos := screen - Vector2i(size)
	if max_pos.x < 0:
		max_pos.x = 0
	if max_pos.y < 0:
		max_pos.y = 0
	position = position.clamp(Vector2i.ZERO, max_pos)

func _screen_size() -> Vector2i:
	var vp := Vector2i.ZERO
	if get_tree() != null and get_tree().root != null:
		vp = Vector2i(get_tree().root.get_visible_rect().size)
	if vp.x <= 0 or vp.y <= 0:
		vp = DisplayServer.screen_get_size()
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2i(1024, 600)
	return vp

func _on_confirmed() -> void:
	if _done:
		return
	_done = true
	var option_id := ""
	if _option_button.selected >= 0:
		option_id = str(_option_button.get_selected_metadata())
	resolved.emit(option_id, false)

func _on_canceled() -> void:
	if _done:
		return
	_done = true
	resolved.emit("", true)
