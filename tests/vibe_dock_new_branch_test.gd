extends GdUnitTestSuite
## The "New…" entry of the status-bar branch dropdown: _refresh_branch() appends
## it behind a separator (int sentinel metadata), picking it opens the
## VibeNewBranchDialog without spawning git, and _create_branch() runs
## `git -C <root> checkout -b <branch>` through the injected fake runner —
## selecting the new branch on success, logging + snapping back on failure.

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


func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_that(f).is_not_null()
	f.store_string(content)
	f.close()


func _mktemp_repo(head_content: String, branches: Array) -> String:
	var dir := "/tmp/vibe_new_branch_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	DirAccess.make_dir_recursive_absolute(dir.path_join(".git"))
	_write(dir.path_join(".git/HEAD"), head_content)
	for b in branches:
		var ref := dir.path_join(".git/refs/heads").path_join(str(b))
		DirAccess.make_dir_recursive_absolute(ref.get_base_dir())
		_write(ref, "0123456789abcdef0123456789abcdef01234567\n")
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


## Fake git runner with the same contract as GitBranch._default_git_runner:
## records every call; on a successful `checkout -b` it also writes the new
## loose ref and rewrites HEAD, like a real git would.
func _fake_runner(calls: Array, repo: String, create_branch: String, exit_code: int, output: String) -> Callable:
	return func(exe: String, args: PackedStringArray) -> Dictionary:
		calls.append({"exe": exe, "args": args})
		if create_branch != "" and exit_code == 0:
			var ref := repo.path_join(".git/refs/heads").path_join(create_branch)
			DirAccess.make_dir_recursive_absolute(ref.get_base_dir())
			_write(ref, "0123456789abcdef0123456789abcdef01234567\n")
			_write(repo.path_join(".git/HEAD"), "ref: refs/heads/%s\n" % create_branch)
		return {"exit_code": exit_code, "output": output}


func _item_index(dock: VibeAcpDock, text: String) -> int:
	for i in dock._branch_option.item_count:
		if dock._branch_option.get_item_text(i) == text:
			return i
	return -1


func _selected_text(dock: VibeAcpDock) -> String:
	var sel := dock._branch_option.selected
	return dock._branch_option.get_item_text(sel) if sel >= 0 else ""


func _new_item_index(dock: VibeAcpDock) -> int:
	return _item_index(dock, "New…")


func _find_dialog(dock: VibeAcpDock) -> VibeNewBranchDialog:
	for c in dock.get_children():
		if c is VibeNewBranchDialog:
			return c as VibeNewBranchDialog
	return null


func test_refresh_branch_appends_new_item_behind_separator_with_sentinel_metadata() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var n := dock._branch_option.item_count
	assert_that(n).is_equal(4)  # feat/x, main, separator, New…
	assert_that(dock._branch_option.get_item_text(n - 1)).is_equal("New…")
	assert_that(dock._branch_option.is_item_separator(n - 2)).is_true()
	assert_that(dock._branch_option.get_item_metadata(n - 1)).is_equal(VibeAcpDock.NEW_BRANCH_ITEM)
	assert_that(_selected_text(dock)).is_equal("main")  # New… is never the selection
	dock.free()


func test_new_item_not_added_when_not_a_repo() -> void:
	var dir := "/tmp/vibe_new_branch_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	DirAccess.make_dir_recursive_absolute(dir)
	_dirs.append(dir)
	var dock := _make_dock()
	dock._project_root = dir
	dock._refresh_branch()
	assert_that(dock._branch_option.item_count).is_equal(0)  # dropdown stays hidden
	assert_that(_new_item_index(dock)).is_equal(-1)
	dock.free()


func test_selecting_new_item_opens_dialog_without_spawning_git_and_snaps_back() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo, "", 0, "")
	var idx := _new_item_index(dock)
	assert_that(idx).is_greater(-1)
	dock._on_branch_selected(idx)
	assert_that(calls).is_empty()  # no git call until a name is confirmed
	assert_that(_find_dialog(dock)).is_not_null()
	assert_that(_selected_text(dock)).is_equal("main")  # selection snapped back
	dock.free()


func test_dialog_ok_creates_and_switches_to_the_new_branch() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo, "feat/new", 0, "Switched to a new branch 'feat/new'")
	dock._on_branch_selected(_new_item_index(dock))
	var dlg := _find_dialog(dock)
	assert_that(dlg).is_not_null()
	dlg._line_edit.text = "feat/new"
	dlg._line_edit.text_changed.emit("feat/new")  # programmatic set doesn't emit it; typing does
	assert_that(dlg.get_ok_button().disabled).is_false()
	dlg._on_confirmed()
	# git was invoked once, as `git -C <root> checkout -b feat/new`
	assert_that(calls.size()).is_equal(1)
	assert_that(calls[0]["args"]).is_equal(PackedStringArray(["-C", repo, "checkout", "-b", "feat/new"]))
	# the fake wrote the ref + HEAD, so the refresh selected the new branch
	assert_that(GitBranch.current_branch(repo)).is_equal("feat/new")
	assert_that(_selected_text(dock)).is_equal("feat/new")
	assert_that(dock._transcript.get_parsed_text()).contains("created and switched to git branch 'feat/new'")
	dock.free()


func test_create_branch_invalid_name_logs_error_without_spawning_git() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo, "", 0, "")
	dock._create_branch("a..b")
	assert_that(calls).is_empty()
	assert_that(dock._transcript.get_parsed_text()).contains("invalid branch name")
	assert_that(_selected_text(dock)).is_equal("main")
	dock.free()


func test_create_branch_existing_branch_logs_error_without_spawning_git() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo, "", 0, "")
	dock._create_branch("feat/x")
	assert_that(calls).is_empty()
	assert_that(dock._transcript.get_parsed_text()).contains("branch 'feat/x' already exists")
	assert_that(_selected_text(dock)).is_equal("main")
	dock.free()


func test_failed_create_snaps_selection_back_and_logs_error() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo, "", 1, "error: Your local changes would be overwritten")
	dock._create_branch("feat/new")
	assert_that(calls.size()).is_equal(1)
	assert_that(GitBranch.current_branch(repo)).is_equal("main")  # HEAD unchanged
	assert_that(_selected_text(dock)).is_equal("main")
	assert_that(dock._transcript.get_parsed_text()).contains("git checkout -b 'feat/new' failed")
	assert_that(dock._transcript.get_parsed_text()).contains("local changes")
	dock.free()
