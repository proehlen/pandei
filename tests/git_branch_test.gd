extends GdUnitTestSuite
## GitBranch: pure .git/HEAD reading for the dock status bar. Covers normal
## repos, branch names with slashes, detached HEAD (raw sha in HEAD), linked
## worktrees (.git as a "gitdir:" file, absolute and relative), and paths
## that are not a git checkout.

var _dirs: Array[String] = []


func after_test() -> void:
	for d in _dirs:
		_remove_recursive(d)
	_dirs.clear()


func _mktemp() -> String:
	var dir := "/tmp/vibe_git_branch_test_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	DirAccess.make_dir_recursive_absolute(dir)
	_dirs.append(dir)
	return dir


func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_that(f).is_not_null()
	f.store_string(content)
	f.close()


func _remove_recursive(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)
	for sub in d.get_directories():
		_remove_recursive(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _make_repo(head_content: String) -> String:
	var root := _mktemp()
	DirAccess.make_dir_recursive_absolute(root.path_join(".git"))
	_write(root.path_join(".git/HEAD"), head_content)
	return root


func test_current_branch_reads_head_ref() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	assert_that(GitBranch.current_branch(root)).is_equal("main")


func test_current_branch_keeps_slashes_in_branch_name() -> void:
	var root := _make_repo("ref: refs/heads/feat/vibe-dock-status-bar\n")
	assert_that(GitBranch.current_branch(root)).is_equal("feat/vibe-dock-status-bar")


func test_detached_head_shows_short_sha() -> void:
	var sha := "a1b2c3d4e5f60123456789abcdef0123456789abcd"  # 40 hex chars
	var root := _make_repo(sha + "\n")
	assert_that(GitBranch.current_branch(root)).is_equal("HEAD@a1b2c3d4")


func test_worktree_with_absolute_gitdir_file() -> void:
	var root := _mktemp()
	var wt_gitdir := _mktemp().path_join("worktrees/wt1")
	DirAccess.make_dir_recursive_absolute(wt_gitdir)
	_write(wt_gitdir.path_join("HEAD"), "ref: refs/heads/wt-branch\n")
	_write(root.path_join(".git"), "gitdir: " + wt_gitdir + "\n")
	assert_that(GitBranch.current_branch(root)).is_equal("wt-branch")


func test_worktree_with_relative_gitdir_file() -> void:
	var root := _mktemp()
	var wt_gitdir := root.path_join("elsewhere/wt")
	DirAccess.make_dir_recursive_absolute(wt_gitdir)
	_write(wt_gitdir.path_join("HEAD"), "ref: refs/heads/rel-branch\n")
	_write(root.path_join(".git"), "gitdir: elsewhere/wt\n")
	assert_that(GitBranch.current_branch(root)).is_equal("rel-branch")


func test_non_repo_returns_empty() -> void:
	assert_that(GitBranch.current_branch(_mktemp())).is_equal("")


func test_empty_or_missing_root_returns_empty() -> void:
	assert_that(GitBranch.current_branch("")).is_equal("")
	assert_that(GitBranch.current_branch("/nonexistent/path/xyz")).is_equal("")


func test_repo_with_git_dir_but_missing_head_returns_empty() -> void:
	var root := _mktemp()
	DirAccess.make_dir_recursive_absolute(root.path_join(".git"))
	assert_that(GitBranch.current_branch(root)).is_equal("")


func test_display_name_edge_cases() -> void:
	assert_that(GitBranch.display_name("")).is_equal("")
	assert_that(GitBranch.display_name("ref: refs/heads/main")).is_equal("main")
	assert_that(GitBranch.display_name("  ref: refs/heads/main\n")).is_equal("main")
	assert_that(GitBranch.display_name("0123456789abcdef")).is_equal("HEAD@01234567")


func test_project_itself_is_a_git_repo_with_a_branch() -> void:
	# the verification workflow always runs inside this git checkout
	var root := ProjectSettings.globalize_path("res://")
	assert_that(GitBranch.current_branch(root)).is_not_empty()


# ---------------------------------------------------------------- list_branches

func _make_loose_ref(root: String, branch: String) -> void:
	var ref := root.path_join(".git/refs/heads").path_join(branch)
	DirAccess.make_dir_recursive_absolute(ref.get_base_dir())
	_write(ref, "0123456789abcdef0123456789abcdef01234567\n")


func test_list_branches_reads_loose_refs_recursively_sorted() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	_make_loose_ref(root, "main")
	_make_loose_ref(root, "feat/x")
	_make_loose_ref(root, "feat/a")
	assert_that(GitBranch.list_branches(root)).is_equal(PackedStringArray(["feat/a", "feat/x", "main"]))


func test_list_branches_reads_packed_refs_and_skips_tags_and_peeled_lines() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	_write(root.path_join(".git/packed-refs"),
		"# pack-refs with: peeled fully-peeled sorted \n" +
		"0123456789abcdef0123456789abcdef01234567 refs/heads/main\n" +
		"0123456789abcdef0123456789abcdef01234567 refs/heads/feat/packed\n" +
		"^89abcdef0123456789abcdef0123456789abcdef01\n" +
		"0123456789abcdef0123456789abcdef01234567 refs/tags/v1.0\n")
	assert_that(GitBranch.list_branches(root)).is_equal(PackedStringArray(["feat/packed", "main"]))


func test_list_branches_loose_ref_wins_over_packed_and_is_not_duplicated() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	_write(root.path_join(".git/packed-refs"),
		"0123456789abcdef0123456789abcdef01234567 refs/heads/main\n" +
		"0123456789abcdef0123456789abcdef01234567 refs/heads/other\n")
	_make_loose_ref(root, "main")
	assert_that(GitBranch.list_branches(root)).is_equal(PackedStringArray(["main", "other"]))


func test_list_branches_non_repo_returns_empty() -> void:
	assert_that(GitBranch.list_branches(_mktemp())).is_empty()
	assert_that(GitBranch.list_branches("")).is_empty()
	assert_that(GitBranch.list_branches("/nonexistent/path/xyz")).is_empty()


func test_list_branches_through_worktree_gitdir_file() -> void:
	var root := _mktemp()
	var wt_gitdir := _mktemp().path_join("worktrees/wt1")
	DirAccess.make_dir_recursive_absolute(wt_gitdir.path_join("refs/heads"))
	_write(wt_gitdir.path_join("HEAD"), "ref: refs/heads/wt-branch\n")
	_write(wt_gitdir.path_join("refs/heads/wt-branch"), "0123456789abcdef0123456789abcdef01234567\n")
	_write(root.path_join(".git"), "gitdir: " + wt_gitdir + "\n")
	assert_that(GitBranch.list_branches(root)).is_equal(PackedStringArray(["wt-branch"]))


# ---------------------------------------------------------------- validation

func test_is_valid_branch_name_accepts_normal_names() -> void:
	for n in ["main", "feat/x", "fix/permission-dialog-overflow", "release-1.2.3", "a_b-c.d"]:
		assert_that(GitBranch.is_valid_branch_name(n)).is_true()


func test_is_valid_branch_name_rejects_illegal_names() -> void:
	for n in ["", "-rf", "a//b", "a..b", "a b", "a~b", "a^b", "a:b", "a?b", "a*b", "a[b", "a\\b",
			"/leading", "trailing/", "ends.dot.", "main.lock", ".hidden", "a/.hidden", "a@{b", "a\tb"]:
		assert_that(GitBranch.is_valid_branch_name(n)).is_false()


# ---------------------------------------------------------------- switch_branch

## Fake runner with the same contract as GitBranch._default_git_runner:
## records the call, optionally returns canned output/exit code.
func _recording_runner(calls: Array, exit_code: int, output: String) -> Callable:
	return func(exe: String, args: PackedStringArray) -> Dictionary:
		calls.append({"exe": exe, "args": args})
		return {"exit_code": exit_code, "output": output}


func test_switch_branch_invokes_git_checkout_with_root_and_branch() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.switch_branch(root, "feat/x", _recording_runner(calls, 0, "Switched to branch 'feat/x'"))
	assert_that(bool(res["ok"])).is_true()
	assert_that(int(res["exit_code"])).is_equal(0)
	assert_that(str(res["output"])).is_equal("Switched to branch 'feat/x'")
	assert_that(calls.size()).is_equal(1)
	assert_that(str(calls[0]["exe"])).is_equal("git")
	assert_that(calls[0]["args"]).is_equal(PackedStringArray(["-C", root, "checkout", "feat/x"]))


func test_switch_branch_propagates_failure_exit_code_and_output() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.switch_branch(root, "feat/x", _recording_runner(calls, 1, "error: local changes"))
	assert_that(bool(res["ok"])).is_false()
	assert_that(int(res["exit_code"])).is_equal(1)
	assert_that(str(res["output"])).contains("local changes")
	assert_that(calls.size()).is_equal(1)


func test_switch_branch_rejects_invalid_name_without_spawning_git() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.switch_branch(root, "../evil", _recording_runner(calls, 0, ""))
	assert_that(bool(res["ok"])).is_false()
	assert_that(str(res["output"])).contains("invalid branch name")
	assert_that(calls).is_empty()


func test_switch_branch_rejects_non_repo_without_spawning_git() -> void:
	var calls: Array = []
	var res := GitBranch.switch_branch("/nonexistent/path/xyz", "main", _recording_runner(calls, 0, ""))
	assert_that(bool(res["ok"])).is_false()
	assert_that(str(res["output"])).contains("not a git checkout")
	assert_that(calls).is_empty()


# ---------------------------------------------------------------- create_branch

func test_create_branch_invokes_git_checkout_dash_b_with_root_and_branch() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.create_branch(root, "feat/x", _recording_runner(calls, 0, "Switched to a new branch 'feat/x'"))
	assert_that(bool(res["ok"])).is_true()
	assert_that(int(res["exit_code"])).is_equal(0)
	assert_that(str(res["output"])).is_equal("Switched to a new branch 'feat/x'")
	assert_that(str(res["branch"])).is_equal("feat/x")
	assert_that(calls.size()).is_equal(1)
	assert_that(str(calls[0]["exe"])).is_equal("git")
	assert_that(calls[0]["args"]).is_equal(PackedStringArray(["-C", root, "checkout", "-b", "feat/x"]))


func test_create_branch_propagates_failure_exit_code_and_output() -> void:
	# e.g. the branch already exists: git checkout -b exits non-zero
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.create_branch(root, "main", _recording_runner(calls, 128, "fatal: a branch named 'main' already exists"))
	assert_that(bool(res["ok"])).is_false()
	assert_that(int(res["exit_code"])).is_equal(128)
	assert_that(str(res["output"])).contains("already exists")
	assert_that(calls.size()).is_equal(1)


func test_create_branch_rejects_invalid_name_without_spawning_git() -> void:
	var root := _make_repo("ref: refs/heads/main\n")
	var calls: Array = []
	var res := GitBranch.create_branch(root, "a..b", _recording_runner(calls, 0, ""))
	assert_that(bool(res["ok"])).is_false()
	assert_that(str(res["output"])).contains("invalid branch name")
	assert_that(calls).is_empty()


func test_create_branch_rejects_non_repo_without_spawning_git() -> void:
	var calls: Array = []
	var res := GitBranch.create_branch("/nonexistent/path/xyz", "feat/x", _recording_runner(calls, 0, ""))
	assert_that(bool(res["ok"])).is_false()
	assert_that(str(res["output"])).contains("not a git checkout")
	assert_that(calls).is_empty()
