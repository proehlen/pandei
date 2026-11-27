class_name VibeThoughtDialog
extends AcceptDialog
## Read-only dialog showing one thought block's full text, opened by clicking the
## "thinking"/"thought" link line in the dock transcript.
##
## get_text is re-called on a short timer while the dialog is visible, so a block
## that is still streaming (label "thinking") live-updates; a finished block
## (label "thought") just shows its final text. The window is clamped into the
## screen (popup_on_screen), so the Close button is always reachable without
## resizing or dragging first.

const DIALOG_MIN_SIZE := Vector2i(480, 240)
const TEXT_MIN_SIZE := Vector2(440, 180)
const POLL_SEC := 0.25

var _label: RichTextLabel
var _get_text: Callable
var _timer: Timer
var _last_shown := ""
var _has_shown := false  # "" is a valid (empty) thought text, so track first render separately

func _init() -> void:
	title = "Vibe thought"
	ok_button_text = "Close"
	min_size = DIALOG_MIN_SIZE
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false  # thought text may contain '['; keep it literal
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.selection_enabled = true  # select/copy parts of the reasoning
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = TEXT_MIN_SIZE
	add_child(_label)
	_timer = Timer.new()
	_timer.wait_time = POLL_SEC
	_timer.timeout.connect(_poll)
	add_child(_timer)
	# OK, Escape and the window X all just close this read-only viewer
	confirmed.connect(func() -> void: queue_free())
	canceled.connect(func() -> void: queue_free())
	close_requested.connect(func() -> void: queue_free())

## label is the block's transcript label ("thinking" while streaming, "thought"
## when done) and drives the window title; get_text returns the block's current
## full text (a Callable so a streaming block keeps updating this dialog).
func setup_dialog(label: String, get_text: Callable) -> void:
	title = "Vibe — " + label
	_get_text = get_text
	_refresh()

func _ready() -> void:
	max_size = _screen_size()
	# start the live-update poll only in-tree: headless tests use the dialog on an
	# out-of-tree dock, where Timer.start() would just log an error
	_timer.start()

func _poll() -> void:
	if is_visible():
		_refresh()

func _refresh() -> void:
	if not _get_text.is_valid():
		return
	var t := str(_get_text.call())
	if not _has_shown or t != _last_shown:
		_has_shown = true
		_last_shown = t
		_label.clear()
		_label.append_text(t if t != "" else "(empty)")

## popup_centered() clamped into the screen. No-op when out of tree (headless
## tests add the dialog to an out-of-tree dock and never show it).
func popup_on_screen() -> void:
	if not is_inside_tree():
		return
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
