extends GdUnitTestSuite
## The editor clamps the vertical splitter between the editor area (+ bottom
## panel) and the full-height Inspector against the active bottom tab's
## combined minimum width. When the Vibe dock's header was an HBoxContainer
## with fixed-width controls, the dock reported ~860px minimum width and the
## splitter could not shrink the Inspector at all. The header must stay an
## HFlowContainer with capped OptionButton widths so the reported minimum
## width stays small and the panel wraps instead of blocking the splitter.

func test_dock_reports_small_minimum_width() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	var min_size := dock.get_combined_minimum_size()
	assert_that(min_size.x).is_less(250.0)
	# the vertical minimum (usability floor) must survive the fix
	assert_that(min_size.y).is_greater_equal(170.0)
	dock.queue_free()

func test_minimum_width_stays_small_with_long_session_and_mode_names() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	# a long stored session title / mode name must not inflate the dock's
	# minimum width (OptionButton.fit_to_longest_item = false caps it)
	dock._session_option.add_item("abc12345 — " + "a very long session title ".repeat(5))
	dock._session_option.select(0)
	dock._mode_option.add_item("a very long approval mode name that would overflow")
	dock._mode_option.select(0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(dock.get_combined_minimum_size().x).is_less(250.0)
	dock.queue_free()

func test_header_is_a_wrapping_flow_container() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	var header: Control = dock.get_child(0)
	assert_that(header is HFlowContainer).is_true()
	assert_that(header.get_combined_minimum_size().x).is_less(250.0)
	dock.queue_free()

func test_input_wraps_long_lines() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	# TextEdit defaults to LINE_WRAPPING_NONE, which clips a long prompt at the
	# box edge; the multi-line input must wrap so typed text stays visible.
	assert_that(dock._input.wrap_mode).is_equal(TextEdit.LINE_WRAPPING_BOUNDARY)
	dock.queue_free()

func test_transcript_has_no_paragraph_separation_override() -> void:
	# paragraph_separation was tried and reverted: it also spaced the internal
	# lines of multiline items (they are paragraphs too), looking like
	# line_separation. Mode separation is done with explicit blank lines instead.
	var dock := VibeAcpDock.new()
	dock._build_ui()
	assert_that(dock._transcript.has_theme_constant_override("paragraph_separation")).is_false()
	assert_that(dock._transcript.has_theme_constant_override("line_separation")).is_false()
	dock.free()
