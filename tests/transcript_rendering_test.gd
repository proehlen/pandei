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
