class_name VibePermissionDialog
extends AcceptDialog
## Modal approval dialog for ACP session/request_permission.
## Emits resolved(option_id, cancelled) exactly once; the caller then answers
## the JSON-RPC request and frees the dialog.
##
## Sizing contract (the dialog used to grow taller than the screen, hiding the
## OK button behind the bottom edge): the raw payload sits in a ScrollContainer
## with a bounded minimum size and the window's max_size is clamped to the
## screen, so the dialog stays fully visible for any payload size.
##
## Readability contract: session/request_permission often carries only a
## toolCallId hash; setup_dialog() accepts the tool_call updates the dock saw
## earlier (known_by_id) so the summary names the actual tool being approved.

signal resolved(option_id: String, cancelled: bool)

const DIALOG_MIN_SIZE := Vector2i(500, 0)
const DETAIL_AREA_MIN_SIZE := Vector2(480, 150)  # bounds the dialog's min height

var _summary: Label
var _raw: Label
var _option_button: OptionButton
var _done := false

func _init() -> void:
	title = "Vibe requests permission"
	min_size = DIALOG_MIN_SIZE
	var vb := VBoxContainer.new()
	vb.add_child(_spacer(2))
	# Bounded scroll area holding ALL text (summary + raw payload): a huge or
	# long-word payload must never inflate the dialog's minimum height — that
	# is what pushed the OK button off-screen. An autowrap Label reports its
	# full wrapped height as minimum size, so text must live inside a
	# ScrollContainer (which does not propagate content min size).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = DETAIL_AREA_MIN_SIZE
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # wrap instead of a horizontal scrollbar
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_summary)
	inner.add_child(_spacer(4))
	_raw = Label.new()
	_raw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_raw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_raw)
	scroll.add_child(inner)
	vb.add_child(scroll)
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
	var screen := _screen_size()
	max_size = screen
	popup_centered()
	size = size.min(screen)
	position = position.clamp(Vector2i.ZERO, screen - size)

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
