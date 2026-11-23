extends GdUnitTestSuite
## Status bar beneath the prompt input: the header keeps only interactive
## controls, while the status info (git branch dropdown, connection/session,
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


func _status_controls(dock: VibeAcpDock) -> Array[Control]:
	return [dock._branch_option, dock._status_label, dock._turn_label, dock._usage_label]


func _selected_branch_text(dock: VibeAcpDock) -> String:
	var sel := dock._branch_option.selected
	return dock._branch_option.get_item_text(sel) if sel >= 0 else ""


func _mktemp_repo(head_content: String, branches: Array = []) -> String:
	var dir := "/tmp/vibe_status_bar_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	DirAccess.make_dir_recursive_absolute(dir.path_join(".git"))
	var f := FileAccess.open(dir.path_join(".git/HEAD"), FileAccess.WRITE)
	f.store_string(head_content)
	f.close()
	for b in branches:
		var ref := dir.path_join(".git/refs/heads").path_join(str(b))
		DirAccess.make_dir_recursive_absolute(ref.get_base_dir())
		var rf := FileAccess.open(ref, FileAccess.WRITE)
		rf.store_string("0123456789abcdef0123456789abcdef01234567\n")
		rf.close()
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


func test_separators_appear_between_all_visible_sections() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	dock._refresh_branch()
	# four sections, three separators; turn/usage empty -> hidden, one bar only
	assert_that(dock._status_seps.size()).is_equal(3)
	assert_that(dock._status_seps[0] == dock._branch_sep).is_true()
	assert_that(dock._branch_option.item_count).is_equal(2)
	assert_that(_selected_branch_text(dock)).is_equal("main")
	assert_that(dock._branch_option.visible).is_true()
	assert_that(dock._status_label.visible).is_true()
	assert_that(dock._turn_label.visible).is_false()   # empty labels take no space
	assert_that(dock._usage_label.visible).is_false()
	assert_that(dock._status_seps[0].visible).is_true()
	assert_that(dock._status_seps[1].visible).is_false()
	assert_that(dock._status_seps[2].visible).is_false()
	# usage arrives while turn is still empty (the reported case): exactly one
	# bar between session and usage — not zero, not a doubled bar
	dock._usage_label.text = "0/400000 tok"
	dock._sync_status_bar()
	assert_that(dock._usage_label.visible).is_true()
	assert_that(dock._status_seps[0].visible).is_true()
	assert_that(dock._status_seps[1].visible).is_true()
	assert_that(dock._status_seps[2].visible).is_false()  # turn still empty
	# turn appears too -> all three bars
	dock._turn_label.text = "working…"
	dock._sync_status_bar()
	for sep in dock._status_seps:
		assert_that(sep.visible).is_true()
	# no git repo -> branch section and its bar hidden together, the rest stay
	dock._project_root = "/nonexistent/path/xyz"
	dock._refresh_branch()
	assert_that(dock._branch_option.item_count).is_equal(0)
	assert_that(dock._branch_option.visible).is_false()
	assert_that(dock._status_seps[0].visible).is_false()
	assert_that(dock._status_seps[1].visible).is_true()
	assert_that(dock._status_seps[2].visible).is_true()
	dock.free()


func test_status_bar_background_is_a_darker_translucent_overlay() -> void:
	var dock := _make_dock()
	var sb := dock._status_bar_bg.get_theme_stylebox("panel")
	assert_that(sb is StyleBoxFlat).is_true()
	var c := (sb as StyleBoxFlat).bg_color
	assert_that(c.a).is_greater(0.05)   # translucent: blends with the panel drawn behind
	assert_that(c.a).is_less(0.95)
	assert_that(c.v).is_less(0.5)        # dark overlay -> renders darker than its surroundings
	dock.free()


func test_status_sections_live_in_status_bar_not_in_header() -> void:
	var dock := _make_dock()
	var header: Control = dock.get_child(0)
	for c in _status_controls(dock):
		assert_that(c.get_parent() == dock._status_bar).is_true()
		assert_that(header.get_children().has(c)).is_false()
	dock.free()


func test_status_sections_use_a_smaller_font_than_the_default() -> void:
	var dock := _make_dock()
	var default_size := dock.get_theme_default_font_size()
	for c in _status_controls(dock):
		var size := c.get_theme_font_size("font_size")
		assert_that(size).is_less(default_size)
		assert_that(size).is_greater_equal(9)
	dock.free()


func test_refresh_branch_selects_branch_and_hides_when_not_a_repo() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("ref: refs/heads/feat/test-branch\n", ["main", "feat/test-branch"])
	dock._refresh_branch()
	assert_that(_selected_branch_text(dock)).is_equal("feat/test-branch")
	assert_that(dock._branch_option.item_count).is_equal(2)
	assert_that(dock._branch_option.visible).is_true()
	assert_that(dock._branch_sep.visible).is_true()
	# switching branches is picked up on the next refresh
	dock._project_root = _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/test-branch"])
	dock._refresh_branch()
	assert_that(_selected_branch_text(dock)).is_equal("main")
	# not a git repo: dropdown empties -> section and its bar hidden, no dangling entry
	dock._project_root = "/nonexistent/path/xyz"
	dock._refresh_branch()
	assert_that(dock._branch_option.item_count).is_equal(0)
	assert_that(dock._branch_option.visible).is_false()
	assert_that(dock._branch_sep.visible).is_false()
	dock.free()


func test_detached_head_shows_short_sha_as_disabled_branch_item() -> void:
	var dock := _make_dock()
	dock._project_root = _mktemp_repo("0123456789abcdef0123456789abcdef01234567\n", ["main"])
	dock._refresh_branch()
	assert_that(_selected_branch_text(dock)).is_equal("HEAD@01234567")
	assert_that(dock._branch_option.is_item_disabled(dock._branch_option.selected)).is_true()
	assert_that(str(dock._branch_option.get_item_metadata(dock._branch_option.selected))).is_equal("")
	# the real local branch is still listed after the detached entry
	assert_that(dock._branch_option.item_count).is_equal(2)
	assert_that(dock._branch_option.get_item_text(1)).is_equal("main")
	dock.free()


func test_status_bar_keeps_dock_minimum_width_small_with_long_text() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	# long status text must not inflate the dock's minimum width (the labels
	# clip + ellipsize, the branch dropdown has fit_to_longest_item off, and
	# the row is a flow container, not an HBox)
	dock._branch_option.add_item("feat/a-very-long-branch-name-that-would-overflow")
	dock._branch_option.select(0)
	dock._status_label.text = "session abc12345 — a very long session title that would overflow"
	dock._usage_label.text = "123456/2000000 tok"
	dock._sync_status_bar()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(dock.get_combined_minimum_size().x).is_less(250.0)
	assert_that(dock._status_bar.get_combined_minimum_size().x).is_less(250.0)
	assert_that(dock._status_bar_bg.get_combined_minimum_size().x).is_less(250.0)
	dock.queue_free()


## The branch dropdown must not make the status row taller than the plain
## labels around it: in-tree its button styleboxes' vertical content margins
## are shaved, so its own minimum height stays at label level (within border
## rounding). (The flow row's combined minimum height is a worst-case wrapped
## sum — pre-existing HFlowContainer behavior — so the per-control height is
## what bounds the rendered single-row height.)
func test_branch_option_is_not_taller_than_the_status_labels() -> void:
	var dock := VibeAcpDock.new()
	add_child(dock)
	await get_tree().process_frame
	await get_tree().process_frame
	var label_h := dock._status_label.get_combined_minimum_size().y
	var option_h := dock._branch_option.get_combined_minimum_size().y
	assert_that(option_h).is_less_equal(label_h + 4.0)
	# sanity: an unshaved default-font OptionButton is clearly taller than this
	var plain := OptionButton.new()
	add_child(plain)
	await get_tree().process_frame
	assert_that(option_h).is_less(plain.get_combined_minimum_size().y + 4.0)
	plain.queue_free()
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
	assert_that(_selected_branch_text(dock)).is_not_empty()
	dock._turn_label.text = "working…"
	dock._usage_label.text = "12/100 tok"
	dock._sync_status_bar()
	await get_tree().process_frame
	for c in _status_controls(dock):
		assert_that(c.visible).is_true()  # all four sections have content now
		assert_that(c.custom_minimum_size.x).is_greater(20.0)
		assert_that(c.size_flags_horizontal & Control.SIZE_EXPAND_FILL).is_not_equal(0)
		assert_that(c.get_combined_minimum_size().x).is_greater(20.0)
		assert_that(c.size.x).is_greater(20.0)  # actually allocated enough width to render
	dock.queue_free()
