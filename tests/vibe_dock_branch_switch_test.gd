extends GdUnitTestSuite
## Branch switching from the status-bar dropdown: picking another local branch
## runs `git -C <root> checkout <branch>` through an injected fake runner (so no
## real process spawns headless), selects the new branch on success, and snaps
## the selection back + logs the error when checkout fails (e.g. dirty tree).

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
	var dir := "/tmp/vibe_branch_switch_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
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
## records every call and optionally rewrites HEAD to simulate a successful
## checkout to `checkout_to`.
func _fake_runner(calls: Array, head_path: String, checkout_to: String, exit_code: int, output: String) -> Callable:
	return func(exe: String, args: PackedStringArray) -> Dictionary:
		calls.append({"exe": exe, "args": args})
		if checkout_to != "":
			_write(head_path, "ref: refs/heads/%s\n" % checkout_to)
		return {"exit_code": exit_code, "output": output}


func _item_index(dock: VibeAcpDock, branch: String) -> int:
	for i in dock._branch_option.item_count:
		if dock._branch_option.get_item_text(i) == branch:
			return i
	return -1


func _selected_text(dock: VibeAcpDock) -> String:
	var sel := dock._branch_option.selected
	return dock._branch_option.get_item_text(sel) if sel >= 0 else ""


func test_refresh_branch_lists_local_branches_sorted_with_current_selected() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["feat/b", "main", "feat/a"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var texts: Array[String] = []
	for i in dock._branch_option.item_count:
		texts.append(dock._branch_option.get_item_text(i))
	# branches sorted, then the separator ("" text) and the "New…" entry
	assert_that(texts).is_equal(["feat/a", "feat/b", "main", "", "New…"])
	assert_that(_selected_text(dock)).is_equal("main")
	dock.free()


func test_selecting_another_branch_checks_it_out_and_selects_it() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo.path_join(".git/HEAD"), "feat/x", 0, "Switched to branch 'feat/x'")
	var idx := _item_index(dock, "feat/x")
	assert_that(idx).is_greater(-1)
	dock._on_branch_selected(idx)
	# git was invoked exactly once, as `git -C <root> checkout feat/x`
	assert_that(calls.size()).is_equal(1)
	assert_that(str(calls[0]["exe"])).is_equal("git")
	assert_that(calls[0]["args"]).is_equal(PackedStringArray(["-C", repo, "checkout", "feat/x"]))
	# the fake rewrote HEAD, so the refresh after the switch selected feat/x
	assert_that(GitBranch.current_branch(repo)).is_equal("feat/x")
	assert_that(_selected_text(dock)).is_equal("feat/x")
	assert_that(dock._transcript.get_parsed_text()).contains("switched to git branch 'feat/x'")
	dock.free()


func test_failed_checkout_snaps_selection_back_and_logs_error() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo.path_join(".git/HEAD"), "", 1, "error: Your local changes would be overwritten")
	dock._on_branch_selected(_item_index(dock, "feat/x"))
	assert_that(calls.size()).is_equal(1)
	# checkout failed: HEAD unchanged, selection snapped back to main, error logged
	assert_that(GitBranch.current_branch(repo)).is_equal("main")
	assert_that(_selected_text(dock)).is_equal("main")
	assert_that(dock._transcript.get_parsed_text()).contains("git checkout 'feat/x' failed")
	assert_that(dock._transcript.get_parsed_text()).contains("local changes")
	dock.free()


func test_selecting_the_current_branch_is_a_no_op() -> void:
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo.path_join(".git/HEAD"), "", 0, "")
	dock._on_branch_selected(_item_index(dock, "main"))
	assert_that(calls).is_empty()
	assert_that(_selected_text(dock)).is_equal("main")
	dock.free()


func test_detached_head_item_does_not_trigger_a_switch() -> void:
	var repo := _mktemp_repo("0123456789abcdef0123456789abcdef01234567\n", ["main"])
	var dock := _make_dock()
	dock._project_root = repo
	dock._refresh_branch()
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo.path_join(".git/HEAD"), "", 0, "")
	assert_that(dock._branch_option.is_item_disabled(0)).is_true()
	dock._on_branch_selected(0)  # the disabled HEAD@sha entry
	assert_that(calls).is_empty()
	assert_that(_selected_text(dock)).is_equal("HEAD@01234567")
	dock.free()


func test_programmatic_refresh_does_not_trigger_a_switch() -> void:
	# _refresh_branch() calls select() internally; whatever the engine's signal
	# semantics are for select(), that must never reach the checkout path
	var repo := _mktemp_repo("ref: refs/heads/main\n", ["main", "feat/x"])
	var dock := _make_dock()
	dock._project_root = repo
	var calls: Array = []
	dock._git_runner = _fake_runner(calls, repo.path_join(".git/HEAD"), "", 0, "")
	dock._refresh_branch()
	dock._refresh_branch()
	assert_that(calls).is_empty()
	assert_that(_selected_text(dock)).is_equal("main")
	dock.free()
