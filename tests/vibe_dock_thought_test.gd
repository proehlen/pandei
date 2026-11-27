extends GdUnitTestSuite
## Thought blocks render as a single clickable "thinking"/"thought" link line —
## the thought text itself is buffered in dock._thoughts_by_id (never appended
## to the transcript) and shown in a VibeThoughtDialog when the link is clicked.
##
## The dock is built with _build_ui() only (no _ready, so no auto-connect), the
## same pattern as the other vibe_dock_* suites.

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

func test_thought_chunks_are_buffered_not_appended_inline() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "let me think "))
	dock._render_update("sid", _thought("m1", "about this"))
	var parsed := dock._transcript.get_parsed_text()
	# the transcript carries only the label link, not the reasoning
	assert_that(parsed.contains("thinking")).is_true()
	assert_that(parsed.contains("let me think")).is_false()
	# chunks of one messageId accumulate into one buffer entry
	assert_that(dock._thoughts_by_id["m1"]).is_equal("let me think about this")
	dock.free()

func test_label_becomes_thought_when_next_agent_chunk_arrives() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "reasoning"))
	dock._render_update("sid", _agent("a1", "answer"))
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("thought\n")).is_true()
	assert_that(parsed.contains("thinking")).is_false()
	assert_that(parsed.contains("Vibe: answer")).is_true()
	# the reasoning never leaked into the transcript
	assert_that(parsed.contains("reasoning")).is_false()
	dock.free()

func test_prompt_finished_renames_a_still_streaming_label_to_thought() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "partial"))
	dock._on_prompt_finished("sid", {}, null)
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("thought\n")).is_true()
	assert_that(parsed.contains("thinking")).is_false()
	assert_that(dock._thought_msg_id).is_equal("")
	dock.free()

func test_tool_line_after_thought_renames_label() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "thinking about tools"))
	dock._render_update("sid", {"sessionUpdate": "tool_call", "toolCallId": "t1",
		"title": "run x", "status": "pending"})
	var parsed := dock._transcript.get_parsed_text()
	assert_that(parsed.contains("thought\n")).is_true()
	assert_that(parsed.contains("tool: run x — pending")).is_true()
	dock.free()

func test_separate_message_ids_get_separate_link_lines() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "first"))
	dock._render_update("sid", _thought("m2", "second"))
	var parsed := dock._transcript.get_parsed_text()
	# m1's block closed when m2 started: renamed to "thought"; m2 still "thinking"
	assert_that(parsed.contains("thought\n")).is_true()
	assert_that(parsed.contains("thinking")).is_true()
	assert_that(dock._thoughts_by_id["m1"]).is_equal("first")
	assert_that(dock._thoughts_by_id["m2"]).is_equal("second")
	dock.free()

func test_streaming_label_animates_dots_without_touching_the_buffer() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "buffered text"))
	assert_that(dock._transcript.get_parsed_text()).is_equal("thinking")
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC)
	assert_that(dock._transcript.get_parsed_text()).is_equal("thinking.")
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC)
	assert_that(dock._transcript.get_parsed_text()).is_equal("thinking..")
	dock._advance_thought_anim(VibeAcpDock.THOUGHT_ANIM_INTERVAL_SEC * 0.5)  # below interval: no change
	assert_that(dock._transcript.get_parsed_text()).is_equal("thinking..")
	# animation only rewrites the short label; the buffered text is untouched and
	# was never sent to the transcript
	assert_that(dock._thoughts_by_id["m1"]).is_equal("buffered text")
	assert_that(dock._transcript.get_parsed_text().contains("buffered text")).is_false()
	dock.free()

func test_animation_is_noop_without_an_open_thought_block() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "hello"))
	dock._close_block()
	var before := dock._transcript.get_parsed_text()
	dock._advance_thought_anim(10.0)
	assert_that(dock._transcript.get_parsed_text()).is_equal(before)
	dock.free()

func test_clicking_the_link_opens_a_dialog_with_the_full_buffered_text() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "all of the reasoning"))
	dock._on_transcript_meta_clicked({"thought_id": "m1"})
	var dlg := _find_thought_dialog(dock)
	assert_that(dlg).is_not_null()
	assert_that(dlg._label.get_parsed_text()).is_equal("all of the reasoning")
	assert_that(dlg.title.contains("thinking")).is_true()  # block still streaming
	# more thinking arrives: the dialog's callable sees the growing buffer
	dock._render_update("sid", _thought("m1", " and more"))
	dlg._refresh()
	assert_that(dlg._label.get_parsed_text()).is_equal("all of the reasoning and more")
	dock.free()

func test_dialog_for_a_finished_block_is_titled_thought() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "x"))
	dock._on_prompt_finished("sid", {}, null)  # closes the block -> "thought"
	dock._on_transcript_meta_clicked({"thought_id": "m1"})
	var dlg := _find_thought_dialog(dock)
	assert_that(dlg).is_not_null()
	assert_that(dlg.title.contains("thought")).is_true()
	assert_that(dlg.title.contains("thinking")).is_false()
	assert_that(dlg._label.get_parsed_text()).is_equal("x")
	dock.free()

func test_new_session_clears_the_thought_buffer_and_label_state() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _thought("m1", "x"))
	dock._on_new_session()
	assert_that(dock._thoughts_by_id).is_empty()
	assert_that(dock._thought_msg_id).is_equal("")
	# the cleared transcript must not get a stale label line re-added
	assert_that(dock._transcript.get_parsed_text().contains("thinking")).is_false()
	assert_that(dock._transcript.get_parsed_text().contains("thought")).is_false()
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
