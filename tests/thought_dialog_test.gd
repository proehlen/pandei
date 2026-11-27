extends GdUnitTestSuite
## VibeThoughtDialog: read-only viewer for one thought block, opened from the
## "Thinking" overlay or a "Thought" link in the transcript. In-tree here (like
## the permission dialog tests) so _ready runs; the dialog is never popped up.

func test_dialog_shows_full_text_and_title_reflects_label() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("Thinking", func() -> String: return "the full thought\nwith two lines")
	assert_that(dlg.title).is_equal("Vibe — Thinking")
	assert_that(dlg._label.get_parsed_text()).is_equal("the full thought\nwith two lines")
	# bbcode stays off: brackets in the thought render literally
	dlg.setup_dialog("Thought", func() -> String: return "array[0] looks fine")
	assert_that(dlg.title).is_equal("Vibe — Thought")
	assert_that(dlg._label.get_parsed_text()).is_equal("array[0] looks fine")
	dlg.queue_free()
	await get_tree().process_frame

func test_dialog_opens_scrolled_to_the_end() -> void:
	# scroll_to_paragraph must exist for the scroll-to-end behavior
	assert_that(ClassDB.class_has_method("RichTextLabel", "scroll_to_paragraph")).is_true()
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("Thought", func() -> String: return "l1\nl2\nl3")
	# the open-time scroll-to-end ran (flag consumed by the first refresh)
	assert_that(dlg._scroll_to_end).is_false()
	dlg.queue_free()
	await get_tree().process_frame

func test_dialog_is_large_enough_to_read_long_thoughts() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	assert_that(dlg.min_size.x).is_greater_equal(600)
	assert_that(dlg.min_size.y).is_greater_equal(400)
	assert_that(dlg._label.custom_minimum_size.x).is_greater_equal(560)
	dlg.queue_free()
	await get_tree().process_frame

func test_dialog_live_updates_while_the_block_streams() -> void:
	# a Dictionary is captured by reference (GDScript lambdas copy plain locals),
	# so the callable below sees later updates — like the dock's _thoughts_by_id
	var state := {"text": "part one"}
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("Thinking", func() -> String: return str(state["text"]))
	assert_that(dlg._label.get_parsed_text()).is_equal("part one")
	state["text"] = "part one part two"
	dlg._refresh()  # the poll timer calls this while visible
	assert_that(dlg._label.get_parsed_text()).is_equal("part one part two")
	dlg.queue_free()
	await get_tree().process_frame

func test_dialog_follows_new_text_only_when_already_at_the_bottom() -> void:
	# long enough to overflow the dialog's text area so the scroll bar has range
	var long_text := ""
	for i in 200:
		long_text += "streaming thought line %d with some text that wraps around\n" % i
	var state := {"text": long_text}
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	dlg.size = Vector2i(700, 500)  # unpopped window: give it a real size so the label overflows
	await get_tree().process_frame
	await get_tree().process_frame
	dlg.setup_dialog("Thinking", func() -> String: return str(state["text"]))
	await get_tree().process_frame
	await get_tree().process_frame
	var sb := dlg._label.get_v_scroll_bar()
	# the open-time scroll-to-end ran and left us at the bottom
	assert_that(dlg._at_bottom()).is_true()
	# new thinking arrives while at the bottom -> the view follows to the new end
	state["text"] = long_text + "fresh tail line\n"
	dlg._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(dlg._label.get_parsed_text()).contains("fresh tail line")
	assert_that(dlg._at_bottom()).is_true()
	# user scrolls back up: new text must NOT yank the view back down
	sb.value = 0.0
	await get_tree().process_frame
	state["text"] = long_text + "fresh tail line\nsecond tail line\n"
	dlg._refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(dlg._label.get_parsed_text()).contains("second tail line")
	assert_that(dlg._at_bottom()).is_false()
	assert_that(sb.value).is_equal(0.0)
	dlg.queue_free()
	await get_tree().process_frame

func test_empty_thought_shows_a_placeholder() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("Thought", func() -> String: return "")
	assert_that(dlg._label.get_parsed_text()).is_equal("(empty)")
	dlg.queue_free()
	await get_tree().process_frame

func test_close_paths_free_the_dialog_exactly_once() -> void:
	var dlg := VibeThoughtDialog.new()
	add_child(dlg)
	await get_tree().process_frame
	dlg.setup_dialog("Thought", func() -> String: return "x")
	dlg.confirmed.emit()  # OK button
	await get_tree().process_frame
	assert_that(is_instance_valid(dlg)).is_false()
