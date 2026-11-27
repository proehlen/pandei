extends GdUnitTestSuite
## Guards the dock's transcript block rendering on a real RichTextLabel:
## Godot 4's method is push_italics() (push_italic does not exist — a call to
## it aborts _open_block mid-way, which once glued all roles onto one line).

func test_role_blocks_render_as_separate_paragraphs() -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(rtl)

	# thought block (color + bold prefix + italics body)
	rtl.push_color(Color.GRAY)
	rtl.push_bold()
	rtl.append_text("thinking: ")
	rtl.pop()
	rtl.push_italics()
	rtl.append_text("The user said hello")
	rtl.append_text("\n")
	rtl.pop()
	rtl.pop()
	# agent block
	rtl.push_color(Color.WHITE)
	rtl.push_bold()
	rtl.append_text("Vibe: ")
	rtl.pop()
	rtl.append_text("Hello! How can I help?")
	rtl.pop()

	assert_that(rtl.get_paragraph_count()).is_equal(2)
	var parsed := rtl.get_parsed_text()
	assert_that(parsed.contains("thinking: The user said hello\n")).is_true()
	assert_that(parsed.contains("Vibe: Hello! How can I help?")).is_true()
	rtl.queue_free()

func test_push_italics_exists() -> void:
	# compile/runtime guard: the method the dock relies on must exist
	assert_that(ClassDB.class_has_method("RichTextLabel", "push_italics")).is_true()
	assert_that(ClassDB.class_has_method("RichTextLabel", "push_italic")).is_false()

func test_append_only_lines_are_stable_in_a_laid_out_rtl() -> void:
	# the dock's transcript is strictly append-only. In a laid-out (sized, in-tree)
	# RichTextLabel, remove_paragraph(count-1) + re-append is NOT a reliable way to
	# rewrite the last line — each call eats one earlier paragraph (reproduced on
	# 4.7.2) — which is why the dock never removes transcript text. This test pins
	# the safe side: plain appends never lose earlier lines.
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.scroll_following = true
	rtl.custom_minimum_size = Vector2(400, 200)
	add_child(rtl)
	await get_tree().process_frame
	for i in 5:
		rtl.append_text("line%d\n" % i)
		await get_tree().process_frame
	assert_that(rtl.get_parsed_text()).is_equal("line0\nline1\nline2\nline3\nline4\n")
	rtl.queue_free()
