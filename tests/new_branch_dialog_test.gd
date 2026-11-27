extends GdUnitTestSuite
## VibeNewBranchDialog: the "New branch" prompt behind the dock's branch
## dropdown "New…" entry. OK stays disabled while the name is empty, invalid
## (GitBranch.is_valid_branch_name) or already a local branch; OK emits
## resolved(name, false) exactly once, Cancel/Escape emits resolved("", true).


func _make_dialog(existing: PackedStringArray = PackedStringArray()) -> VibeNewBranchDialog:
	var dlg := VibeNewBranchDialog.new()
	add_child(dlg)
	dlg.setup_dialog(existing)
	return dlg


## Set the name like a user typing would: in Godot 4 a programmatic
## LineEdit.text set does NOT emit text_changed, so emit it explicitly.
func _set_name(dlg: VibeNewBranchDialog, branch_name: String) -> void:
	dlg._line_edit.text = branch_name
	dlg._line_edit.text_changed.emit(branch_name)


func test_ok_disabled_while_name_empty() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	assert_that(dlg._line_edit.text).is_empty()
	assert_that(dlg.get_ok_button().disabled).is_true()
	assert_that(dlg._hint.text).is_empty()
	dlg.queue_free()
	await get_tree().process_frame


func test_valid_name_enables_ok() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	_set_name(dlg, "feat/my-branch")
	assert_that(dlg.get_ok_button().disabled).is_false()
	assert_that(dlg._hint.text).is_empty()
	dlg.queue_free()
	await get_tree().process_frame


func test_invalid_name_disables_ok_with_hint() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	for bad in ["a..b", "-rf", "has space", "a~b", "main.lock"]:
		_set_name(dlg, bad)
		assert_that(dlg.get_ok_button().disabled).is_true()
		assert_that(dlg._hint.text).is_equal("not a valid branch name")
	dlg.queue_free()
	await get_tree().process_frame


func test_existing_branch_disables_ok_with_hint() -> void:
	var dlg := _make_dialog(PackedStringArray(["main", "feat/x"]))
	await get_tree().process_frame
	_set_name(dlg, "feat/x")
	assert_that(dlg.get_ok_button().disabled).is_true()
	assert_that(dlg._hint.text).contains("already exists")
	_set_name(dlg, "feat/y")
	assert_that(dlg.get_ok_button().disabled).is_false()
	dlg.queue_free()
	await get_tree().process_frame


func test_ok_emits_stripped_name_exactly_once() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	_set_name(dlg, "  feat/new  ")
	var got: Array = []
	dlg.resolved.connect(func(branch: String, cancelled: bool) -> void: got.append([branch, cancelled]))
	dlg.get_ok_button().pressed.emit()  # Button has no press() in 4.x; emit the signal
	dlg.get_ok_button().pressed.emit()  # second press must not re-emit
	assert_that(got).is_equal([["feat/new", false]])
	dlg.queue_free()
	await get_tree().process_frame


func test_enter_in_line_edit_confirms_like_ok() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	_set_name(dlg, "fix/typo")
	var got: Array = []
	dlg.resolved.connect(func(branch: String, cancelled: bool) -> void: got.append([branch, cancelled]))
	dlg._line_edit.text_submitted.emit("fix/typo")
	assert_that(got).is_equal([["fix/typo", false]])
	dlg.queue_free()
	await get_tree().process_frame


func test_enter_with_invalid_name_emits_nothing() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	_set_name(dlg, "a..b")
	var got: Array = []
	dlg.resolved.connect(func(branch: String, cancelled: bool) -> void: got.append([branch, cancelled]))
	dlg._line_edit.text_submitted.emit("a..b")
	dlg.get_ok_button().pressed.emit()  # OK is disabled; must not emit either
	assert_that(got).is_empty()
	dlg.queue_free()
	await get_tree().process_frame


func test_cancel_emits_cancelled_exactly_once() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	_set_name(dlg, "feat/new")
	var got: Array = []
	dlg.resolved.connect(func(branch: String, cancelled: bool) -> void: got.append([branch, cancelled]))
	dlg.canceled.emit()  # AcceptDialog has no cancel() method in 4.x
	dlg.canceled.emit()
	assert_that(got).is_equal([["", true]])
	dlg.queue_free()
	await get_tree().process_frame


func test_dialog_has_ok_and_cancel_buttons() -> void:
	var dlg := _make_dialog()
	await get_tree().process_frame
	assert_that(dlg.get_ok_button()).is_not_null()
	assert_that(dlg.get_ok_button().text).is_equal("OK")
	assert_that(dlg.get_cancel_button()).is_not_null()
	assert_that(dlg.get_cancel_button().text).is_equal("Cancel")
	assert_that(dlg.get_cancel_button().visible).is_true()
	dlg.queue_free()
	await get_tree().process_frame
