class_name VibePermissionDialog
extends AcceptDialog
## Modal approval dialog for ACP session/request_permission.
## Emits resolved(option_id, cancelled) exactly once; the caller then answers
## the JSON-RPC request and frees the dialog.

signal resolved(option_id: String, cancelled: bool)

var _detail: Label
var _option_button: OptionButton
var _done := false

func _init() -> void:
	title = "Vibe requests permission"
	min_size = Vector2i(440, 200)
	var vb := VBoxContainer.new()
	vb.add_child(_spacer(4))
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_detail)
	vb.add_child(_spacer(4))
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

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func setup_dialog(tool_call: Dictionary, options: Array) -> void:
	_detail.text = _describe(tool_call)
	_option_button.clear()
	for i in options.size():
		var o: Dictionary = options[i]
		_option_button.add_item(str(o.get("name", o.get("optionId", "Allow"))))
		_option_button.set_item_metadata(i, str(o.get("optionId", "")))
	if options.size() > 0:
		_option_button.select(0)

func _describe(tool_call: Dictionary) -> String:
	var title := str(tool_call.get("title", "tool call"))
	var kind := str(tool_call.get("kind", ""))
	var raw := JSON.stringify(tool_call, "  ")
	if raw.length() > 1500:
		raw = raw.substr(0, 1500) + "…"
	var header := title
	if kind != "":
		header += "  [kind: %s]" % kind
	return header + "\n\n" + raw

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
