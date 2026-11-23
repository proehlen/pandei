extends GdUnitTestSuite
## Status bar beneath the prompt input: the header keeps only interactive
## controls, while the passive status text (git branch, connection/session,
## turn state, token usage) lives in a slim HFlowContainer row below the
## input row with a smaller font than the editor default. The row must stay
## an HFlowContainer so it never inflates the dock's minimum width (the
## Inspector splitter constraint — see vibe_dock_layout_test.gd).

var _dirs: Array[String] = []


func after_test() -> void:
	for d in _dirs:
		_remove_recursive(d)
	_dirs.clear()


## Controls exist, but _ready()/auto-connect never runs (dock never enters
## the tree), so no real vibe-acp process is spawned.
func _make_dock() -> VibeAcpDock:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	return dock


func _status_labels(dock: VibeAcpDock) -> Array[Label]:
	return [dock._branch_label, dock._status_label, dock._turn_label, dock._usage_label]


func _mktemp_repo(head_content: String) -> String:
	var dir := "/tmp/vibe_status_bar_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	DirAccess.make_dir_recursive_absolute(dir.path_join(".git"))
	var f := FileAccess.open(dir.path_join(".git/HEAD"), FileAccess.WRITE)
	f.store_string(head_content)
	f.close()
	_dirs.append(dir)
	return dir


func _remove_recursive(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
	for sub in d.get_directories():
		_remove_recursive(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func test_status_bar_is_last_child_below_the_input_row() -> void:
	var dock := _make_dock()
	# the status row is a PanelContainer (background strip) wrapping the flow row
	var last: Control = dock.get_child(dock.get_child_count() - 1)
	assert_that(last == dock._status_bar_bg).is_true()
	assert_that(dock._status_bar_bg is PanelContainer).is_true()
	assert_that(dock._status_bar.get_parent() == dock._status_bar_bg).is_true()
	assert_that(dock._status_bar is HFlowContainer).is_true()
	var children := dock.get_children()
	var input_idx := children.find(dock._input_row)
	var bar_idx := children.find(dock._status_bar_bg)
	assert_that(input_idx).is_greater(-1)
	assert_that(bar_idx).is_greater(input_idx)
	dock.free()


func test_separators_between_all_sections_follow_neighbor_text() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("ref: refs/heads/main\n")
	dock._refresh_branch()
	# four sections, three separators; turn/usage empty -> only sep after branch
	assert_that(dock._status_seps.size()).is_equal(3)
	assert_that(dock._status_seps[0] == dock._branch_sep).is_true()
	assert_that(dock._status_seps[0].visible).is_true()
	assert_that(dock._status_seps[1].visible).is_false()
	assert_that(dock._status_seps[2].visible).is_false()
	# turn and usage appear -> all separators visible
	dock._turn_label.text = "working…"
	dock._usage_label.text = "12/100 tok"
	dock._sync_status_separators()
	for sep in dock._status_seps:
		assert_that(sep.visible).is_true()
	# no git repo -> branch label and its separator hidden, the rest stay
	dock._project_root = "/nonexistent/path/xyz"
	dock._refresh_branch()
	assert_that(dock._branch_label.visible).is_false()
	assert_that(dock._status_seps[0].visible).is_false()
	assert_that(dock._status_seps[1].visible).is_true()
	assert_that(dock._status_seps[2].visible).is_true()
	dock.free()


func test_status_bar_background_is_a_darker_panel_stylebox_in_tree() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	var sb := dock._status_bar_bg.get_theme_stylebox("panel")
	assert_that(sb is StyleBoxFlat).is_true()
	# darker (lower brightness) than the plain themed PanelContainer background
	var panel_bg := dock.get_theme_stylebox("panel", "PanelContainer")
	if panel_bg is StyleBoxFlat and panel_bg.bg_color.a > 0.0:
		assert_that((sb as StyleBoxFlat).bg_color.v).is_less(panel_bg.bg_color.v)
	dock.queue_free()


func test_status_labels_live_in_status_bar_not_in_header() -> void:
	var dock := _make_dock()
	var header: Control = dock.get_child(0)
	for l in _status_labels(dock):
		assert_that(l.get_parent() == dock._status_bar).is_true()
		assert_that(header.get_children().has(l)).is_false()
	dock.free()


func test_status_labels_use_a_smaller_font_than_the_default() -> void:
	var dock := _make_dock()
	var default_size := dock.get_theme_default_font_size()
	for l in _status_labels(dock):
		var size := l.get_theme_font_size("font_size")
		assert_that(size).is_less(default_size)
		assert_that(size).is_greater_equal(9)
	dock.free()


func test_refresh_branch_shows_branch_and_hides_when_not_a_repo() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("ref: refs/heads/feat/test-branch\n")
	dock._refresh_branch()
	assert_that(dock._branch_label.text).is_equal("git: feat/test-branch")
	assert_that(dock._branch_label.visible).is_true()
	assert_that(dock._branch_sep.visible).is_true()
	# switching branches is picked up on the next refresh
	dock._project_root = _mktemp_repo("ref: refs/heads/main\n")
	dock._refresh_branch()
	assert_that(dock._branch_label.text).is_equal("git: main")
	# not a git repo: no dangling "git:" label
	dock._project_root = "/nonexistent/path/xyz"
	dock._refresh_branch()
	assert_that(dock._branch_label.text).is_equal("")
	assert_that(dock._branch_label.visible).is_false()
	assert_that(dock._branch_sep.visible).is_false()
	dock.free()


func test_detached_head_shows_short_sha_in_branch_label() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("0123456789abcdef0123456789abcdef01234567\n")
	dock._refresh_branch()
	assert_that(dock._branch_label.text).is_equal("git: HEAD@01234567")
	dock.free()


func test_status_bar_keeps_dock_minimum_width_small_with_long_text() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	# long status text must not inflate the dock's minimum width (the labels
	# clip + ellipsize and the row is a flow container, not an HBox)
	dock._branch_label.text = "git: feat/a-very-long-branch-name-that-would-overflow"
	dock._status_label.text = "session abc12345 — a very long session title that would overflow"
	dock._usage_label.text = "123456/2000000 tok"
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(dock.get_combined_minimum_size().x).is_less(250.0)
	assert_that(dock._status_bar.get_combined_minimum_size().x).is_less(250.0)
	assert_that(dock._status_bar_bg.get_combined_minimum_size().x).is_less(250.0)
	dock.queue_free()


## Regression test for the "empty status bar" bug: a Label with
## text_overrun_behavior collapses its minimum width to ~0 inside a flow
## container, so without an explicit custom_minimum_size.x floor + EXPAND_FILL
## the labels are allocated ~1px and render nothing (only the separator shows).
func test_status_labels_get_real_allocated_width_in_tree() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	dock.set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# _ready() ran _refresh_branch() and this repo is a git checkout
	assert_that(dock._branch_label.text).is_not_empty()
	for l in _status_labels(dock):
		assert_that(l.custom_minimum_size.x).is_greater(20.0)
		assert_that(l.size_flags_horizontal & Control.SIZE_EXPAND_FILL).is_not_equal(0)
		assert_that(l.get_combined_minimum_size().x).is_greater(20.0)
		assert_that(l.size.x).is_greater(20.0)  # actually allocated enough width to render
	dock.queue_free()
