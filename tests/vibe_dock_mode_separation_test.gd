extends GdUnitTestSuite
## Blank-line separation between transcript "modes": a whole blank line is inserted
## when the mode changes (You / Vibe / Thought / tool run / sys), and consecutive
## items of the same mode stay grouped — a run of tool lines, or several "Thought"
## links, get no blank lines between them. Multiline items keep their internal
## lines tight (no paragraph_separation; the blank line only goes between
## top-level items).

func _thought(mid: String, text: String) -> Dictionary:
	return {"sessionUpdate": "agent_thought_chunk", "messageId": mid,
		"content": {"type": "text", "text": text}}

func _agent(mid: String, text: String) -> Dictionary:
	return {"sessionUpdate": "agent_message_chunk", "messageId": mid,
		"content": {"type": "text", "text": text}}

func _tool(tid: String, title: String) -> Dictionary:
	return {"sessionUpdate": "tool_call", "toolCallId": tid, "title": title, "status": "pending"}

func test_blank_line_between_user_and_agent() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._append_line_role(TranscriptRoles.ROLE_USER, "hi")
	dock._render_update("sid", _agent("a1", "hello"))
	dock._close_block()
	assert_that(dock._transcript.get_parsed_text()).is_equal("You: hi\n\nVibe: hello\n")
	dock.free()

func test_no_blank_line_on_first_item_or_same_mode() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "one"))
	dock._render_update("sid", _agent("a2", "two"))  # another agent message: mode unchanged
	dock._close_block()
	assert_that(dock._transcript.get_parsed_text()).is_equal("Vibe: one\nVibe: two\n")
	dock.free()

func test_tool_run_is_grouped_but_separated_from_other_modes() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "answer"))
	dock._render_update("sid", _tool("t1", "run x"))
	dock._render_update("sid", _tool("t2", "run y"))  # same tool run: no blank line
	dock._render_update("sid", _agent("a2", "after tools"))
	dock._close_block()
	assert_that(dock._transcript.get_parsed_text()).is_equal(
		"Vibe: answer\n\ntool: run x — pending\ntool: run y — pending\n\nVibe: after tools\n")
	dock.free()

func test_thought_link_line_is_separated_and_groups_with_itself() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "answer"))
	dock._render_update("sid", _thought("m1", "first thought"))
	dock._render_update("sid", _thought("m2", "second thought"))  # closes m1 -> "Thought" line
	dock._on_prompt_finished("sid", {}, null)  # closes m2 -> another "Thought" line
	var parsed := dock._transcript.get_parsed_text()
	# blank line before the first Thought (mode change agent -> thought), but the
	# two consecutive Thought lines are grouped (same mode)
	assert_that(parsed).is_equal("Vibe: answer\n\nThought\nThought\n")
	dock.free()

func test_sys_lines_are_their_own_mode() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._append_line_role(TranscriptRoles.ROLE_SYS, "session ready: abc")
	dock._append_line_role(TranscriptRoles.ROLE_SYS, "another log line")
	dock._append_line_role(TranscriptRoles.ROLE_USER, "hi")
	assert_that(dock._transcript.get_parsed_text()).is_equal(
		"[sys] session ready: abc\n[sys] another log line\n\nYou: hi\n")
	dock.free()

func test_multiline_item_keeps_internal_lines_tight() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "line one\nline two\nline three"))
	dock._close_block()
	# no blank lines inside a single multiline message
	assert_that(dock._transcript.get_parsed_text()).is_equal("Vibe: line one\nline two\nline three\n")
	dock.free()

func test_new_session_resets_mode_so_no_leading_blank_line() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock._render_update("sid", _agent("a1", "old"))
	dock._close_block()
	dock._on_new_session()  # clears the transcript and resets _last_mode
	assert_that(dock._transcript.get_parsed_text().begins_with("\n")).is_false()
	dock.free()
