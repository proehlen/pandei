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
