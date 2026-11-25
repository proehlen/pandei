class_name VibeNewBranchDialog
extends ConfirmationDialog
## Modal "New branch" dialog for the dock's branch dropdown: a LineEdit for
## the branch name plus the ConfirmationDialog's OK and Cancel buttons.
## Emits resolved(branch_name, cancelled) exactly once; the caller then runs
## `git checkout -b` and frees the dialog.
##
## The OK button stays disabled while the entered name is empty, not a valid
## git refname (GitBranch.is_valid_branch_name), or already a local branch
## (setup_dialog receives the current listing); the hint label says why.
## Enter in the LineEdit confirms, same as OK.

signal resolved(branch_name: String, cancelled: bool)

const DIALOG_MIN_SIZE := Vector2i(360, 0)
const HINT_COLOR := Color(1.00, 0.50, 0.45)

var _line_edit: LineEdit
var _hint: Label
var _existing: PackedStringArray = []
var _done := false

func _init() -> void:
	title = "Create new branch"
	# ConfirmationDialog provides OK and Cancel; Cancel (and Escape / window
	# close) takes the canceled path below.
	min_size = DIALOG_MIN_SIZE
	var vb := VBoxContainer.new()
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Branch name:"
	row.add_child(lbl)
	_line_edit = LineEdit.new()
	_line_edit.custom_minimum_size.x = 280
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.placeholder_text = "feat/my-branch"
	_line_edit.text_changed.connect(func(_new_text: String) -> void: _validate())
	_line_edit.text_submitted.connect(func(_new_text: String) -> void: _on_confirmed())
	row.add_child(_line_edit)
	vb.add_child(row)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", HINT_COLOR)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_hint)
	add_child(vb)
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	_validate()

## Pass the current local branches (GitBranch.list_branches) so the dialog can
## reject names that already exist before any `git` call happens.
func setup_dialog(existing_branches: PackedStringArray) -> void:
	_existing = existing_branches
	_validate()

## Enable OK only for a usable name; the hint says why not.
func _validate() -> void:
	var name := _line_edit.text.strip_edges()
	var why := ""
	if name.is_empty():
		why = ""
	elif not GitBranch.is_valid_branch_name(name):
		why = "not a valid branch name"
	elif _existing.has(name):
		why = "branch '%s' already exists" % name
	_hint.text = why
	get_ok_button().disabled = not why.is_empty() or name.is_empty()

func _on_confirmed() -> void:
	if _done:
		return
	# Re-validate here: setting LineEdit.text programmatically does not emit
	# text_changed in Godot 4, so OK must never confirm an unvalidated name.
	_validate()
	if get_ok_button().disabled:
		return
	_done = true
	resolved.emit(_line_edit.text.strip_edges(), false)

func _on_canceled() -> void:
	if _done:
		return
	_done = true
	resolved.emit("", true)

## popup_centered(), but only when actually in the tree (headless tests add the
## dialog to an out-of-tree dock and never show it).
func popup_on_screen() -> void:
	if not is_inside_tree():
		return
	popup_centered()
	_line_edit.grab_focus()
