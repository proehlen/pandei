extends GdUnitTestSuite
## VibeThoughtDialog: read-only viewer for one thought block, opened from the
## transcript's "thinking"/"thought" link. In-tree here (like the permission
## dialog tests) so _ready runs; the dialog is never popped up.

func test_dialog_shows_full_text_and_title_reflects_label() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("thinking", func() -> String: return "the full thought\nwith two lines")
	assert_that(dlg.title).is_equal("Vibe — thinking")
	assert_that(dlg._label.get_parsed_text()).is_equal("the full thought\nwith two lines")
	# bbcode stays off: brackets in the thought render literally
	dlg.setup_dialog("thought", func() -> String: return "array[0] looks fine")
	assert_that(dlg.title).is_equal("Vibe — thought")
	assert_that(dlg._label.get_parsed_text()).is_equal("array[0] looks fine")
	dlg.queue_free()
	await get_tree().process_frame

func test_dialog_live_updates_while_the_block_streams() -> void:
	# a Dictionary is captured by reference (GDScript lambdas copy plain locals),
	# so the callable below sees later updates — like the dock's _thoughts_by_id
	var state := {"text": "part one"}
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("thinking", func() -> String: return str(state["text"]))
	assert_that(dlg._label.get_parsed_text()).is_equal("part one")
	state["text"] = "part one part two"
	dlg._refresh()  # the poll timer calls this while visible
	assert_that(dlg._label.get_parsed_text()).is_equal("part one part two")
	dlg.queue_free()
	await get_tree().process_frame

func test_empty_thought_shows_a_placeholder() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("thought", func() -> String: return "")
	assert_that(dlg._label.get_parsed_text()).is_equal("(empty)")
	dlg.queue_free()
	await get_tree().process_frame

func test_close_paths_free_the_dialog_exactly_once() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("thought", func() -> String: return "x")
	dlg.confirmed.emit()  # OK button
	await get_tree().process_frame
	assert_that(is_instance_valid(dlg)).is_false()
