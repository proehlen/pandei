extends GdUnitTestSuite
## Thought blocks: the text is buffered per messageId (never appended to the
## transcript). While a block streams, a "Thinking" LinkButton overlay at the
## bottom of the chat animates (dots) and opens the thought dialog on click; when
## the block closes, a static clickable "Thought" link line is appended to the
## transcript. The transcript RichTextLabel is strictly append-only — rewriting a
## paragraph via remove_paragraph proved unreliable in a laid-out RTL (each call
## ate one earlier line), so the dock never removes/rewrites transcript text.
##
## The dock is built with _build_ui() only (no _ready, so no auto-connect), the
## same pattern as the other vibe_dock_* suites — except the in-tree regression
## test at the bottom, which needs a real laid-out transcript.

func _thought(mid: String, text: String) -> Dictionary:
	return {"sessionUpdate": "agent_thought_chunk", "messageId": mid,
		"content": {"type": "text", "text": text}}

func _agent(mid: String, text: String) -> Dictionary:
	return {"sessionUpdate": "agent_message_chunk", "messageId": mid,
		"content": {"type": "text", "text": text}}

func _find_thought_dialog(dock: VibeAcpDock) -> VibeThoughtDialog:
	for c in dock.get_children():
		if c is VibeThoughtDialog:
			return c as VibeThoughtDialog
	return null

func test_thought_chunks_are_buffered_and_show_live_overlay_not_inline() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "let me think "))
	dock._render_update("sid", _thought("m1", "about this"))
	var parsed := dock._transcript.get_parsed_text()
	# the reasoning never enters the transcript; chunks accumulate in the buffer
	assert_that(parsed.contains("let me think")).is_false()
	assert_that(dock._thoughts_by_id["m1"]).is_equal("let me think about this")
	# the live indicator is the overlay link, visible and labeled "Thinking"
	assert_that(dock._thought_link.visible).is_true()
	assert_that(dock._thought_link.text).is_equal("Thinking")
	assert_that(parsed.contains("Thinking")).is_false()
	dock.free()

func test_finished_block_appends_a_static_thought_link_line() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "reasoning"))
	dock._render_update("sid", _agent("a1", "answer"))
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("Thought\n")).is_true()
	assert_that(parsed.contains("Vibe: answer")).is_true()
	assert_that(parsed.contains("reasoning")).is_false()  # text still not inline
	assert_that(dock._thought_link.visible).is_false()  # overlay hidden
	assert_that(dock._thought_msg_id).is_equal("")
	dock.free()

func test_prompt_finished_appends_thought_line_for_a_still_streaming_block() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "partial"))
	dock._on_prompt_finished("sid", {}, null)
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("Thought\n")).is_true()
	assert_that(parsed.contains("Thinking")).is_false()
	assert_that(dock._thought_msg_id).is_equal("")
	dock.free()

func test_tool_line_after_thought_appends_thought_line() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "thinking about tools"))
	dock._render_update("sid", {"sessionUpdate": "tool_call", "toolCallId": "t1",
		"title": "run x", "status": "pending"})
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("Thought\n")).is_true()
	assert_that(parsed.contains("tool: run x — pending")).is_true()
	dock.free()

func test_separate_message_ids_get_separate_thought_link_lines() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "first"))
	dock._render_update("sid", _thought("m2", "second"))
	var parsed := dock._transcript.get_parsed_text()
	# m1's block closed when m2 started: one static "Thought" line; m2 still live
	assert_that(parsed.contains("Thought\n")).is_true()
	assert_that(dock._thought_link.visible).is_true()
	assert_that(dock._thought_link.text).is_equal("Thinking")
	assert_that(dock._thoughts_by_id["m1"]).is_equal("first")
	assert_that(dock._thoughts_by_id["m2"]).is_equal("second")
	dock.free()

func test_animation_updates_only_the_overlay_link_never_the_transcript() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "earlier answer"))
	dock._close_block()
	var before := dock._transcript.get_parsed_text()
	dock._render_update("sid", _thought("m1", "buffered text"))
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC)
	assert_that(dock._thought_link.text).is_equal("Thinking.")
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC)
	assert_that(dock._thought_link.text).is_equal("Thinking..")
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC * 0.5)  # below interval: no change
	assert_that(dock._thought_link.text).is_equal("Thinking..")
	# the transcript is completely untouched by the animation (no line eating),
	# and the buffer was never sent to the transcript
	assert_that(dock._transcript.get_parsed_text()).is_equal(before)
	assert_that(dock._transcript.get_parsed_text().contains("buffered text")).is_false()
	assert_that(dock._thoughts_by_id["m1"]).is_equal("buffered text")
	dock.free()

func test_animation_is_noop_without_an_open_thought_block() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "hello"))
	dock._close_block()
	dock._advance_thought_anim(10.0)
	assert_that(dock._thought_link.visible).is_false()
	assert_that(dock._transcript.get_parsed_text()).is_equal("Vibe: hello\n")
	dock.free()

func test_clicking_a_finished_thought_link_opens_dialog_with_full_text() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "all of the reasoning"))
	dock._on_prompt_finished("sid", {}, null)  # closes the block -> "Thought" line
	dock._on_transcript_meta_clicked({"thought_id": "m1"})
	var dlg := _find_thought_dialog(dock)
	assert_that(dlg).is_not_null()
	assert_that(dlg._label.get_parsed_text()).is_equal("all of the reasoning")
	assert_that(dlg.title.contains("Thought")).is_true()
	dock.free()

func test_clicking_the_live_thinking_overlay_opens_a_live_updating_dialog() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "part one"))
	dock._thought_link.pressed.emit()  # user clicks the "Thinking" overlay
	var dlg := _find_thought_dialog(dock)
	assert_that(dlg).is_not_null()
	assert_that(dlg._label.get_parsed_text()).is_equal("part one")
	assert_that(dlg.title.contains("Thinking")).is_true()
	# more thinking arrives: the dialog's callable sees the growing buffer
	dock._render_update("sid", _thought("m1", " part two"))
	dlg._refresh()
	assert_that(dlg._label.get_parsed_text()).is_equal("part one part two")
	dock.free()

func test_new_session_clears_thought_buffer_overlay_and_lines() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "x"))
	dock._on_new_session()
	assert_that(dock._thoughts_by_id).is_empty()
	assert_that(dock._thought_msg_id).is_equal("")
	assert_that(dock._thought_link.visible).is_false()
	# the cleared transcript must not get a stale "Thought" line re-added
	assert_that(dock._transcript.get_parsed_text().contains("Thought")).is_false()
	dock.free()

func test_thought_buffer_is_capped() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	for i in VibeAcpDock.MAX_THOUGHTS_KEPT + 10:
		dock._render_update("sid", _thought("m%d" % i, "t%d" % i))
	assert_that(dock._thoughts_by_id.size()).is_equal(VibeAcpDock.MAX_THOUGHTS_KEPT)
	assert_that(dock._thoughts_by_id.has("m0")).is_false()  # oldest dropped
	assert_that(dock._thoughts_by_id.has("m%d" % (VibeAcpDock.MAX_THOUGHTS_KEPT + 9))).is_true()
	dock.free()

func test_in_tree_animation_does_not_eat_transcript_lines() -> void:
	# Regression for the reported bug: in a real (laid-out) editor the animated
	# label's remove_paragraph(count-1) rewrite ate one earlier transcript line
	# per tick until only the label remained. The transcript must be append-only:
	# after many animation ticks with a thought block open, every earlier line
	# must still be there.
	var dock := VibeAcpDock.new()
	add_child(dock)  # _ready runs (spawns vibe-acp briefly, like the layout tests) ...
	dock.shutdown()  # ... kill it immediately: no client -> no pump, no real updates
	await get_tree().process_frame
	await get_tree().process_frame
	dock._render_update("sid", _agent("a1", "line one"))
	dock._render_update("sid", _agent("a2", "line two"))
	dock._close_block()
	dock._render_update("sid", _thought("m1", "secret reasoning"))
	for i in 8:
		dock._advance_thought_anim(0.5)  # simulate _process ticks (plus real frames below)
		await get_tree().process_frame  # _process also runs the animation itself
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("line one")).is_true()
	assert_that(parsed.contains("line two")).is_true()
	assert_that(parsed.contains("secret reasoning")).is_false()
	assert_that(dock._thought_link.visible).is_true()
	dock.queue_free()
	await get_tree().process_frame
