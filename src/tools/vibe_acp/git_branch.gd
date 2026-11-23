class_name GitBranch
extends RefCounted
## Git branch helpers for the dock's status bar: reads the current branch and
## lists all local branches of a project, and switches branches on request.
## Reads are pure file reads (no `git` process spawn) so they are cheap enough
## to poll on a timer and trivially testable headless; only switch_branch()
## spawns `git checkout`, behind an injectable runner for tests.
## `.git/HEAD` holds either "ref: refs/heads/<branch>" or a raw commit sha
## (detached HEAD); in linked worktrees/submodules `.git` is a file containing
## "gitdir: <path>".

const HEAD_REF_PREFIX := "ref: refs/heads/"
const GITDIR_PREFIX := "gitdir:"
const SHORT_SHA_LENGTH := 8

## Resolve the git dir for project_root: a normal repo has a `.git`
## directory; a linked worktree/submodule has a `.git` FILE whose content is
## "gitdir: <path>" (absolute, or relative to project_root).
## Returns "" when project_root is not a git checkout.
static func resolve_git_dir(project_root: String) -> String:
	if project_root == "":
		return ""
	var dot_git := project_root.path_join(".git")
	if FileAccess.file_exists(dot_git):
		var f := FileAccess.open(dot_git, FileAccess.READ)
		if f != null:
			var content := f.get_as_text().strip_edges()
			f.close()
			if content.begins_with(GITDIR_PREFIX):
				var p := content.substr(GITDIR_PREFIX.length()).strip_edges()
				if not p.is_absolute_path():
					p = project_root.path_join(p)
				return p
		return dot_git
	if DirAccess.dir_exists_absolute(dot_git):
		return dot_git
	return ""

## Raw content of git_dir/HEAD, or "" when unreadable.
static func read_head(git_dir: String) -> String:
	if git_dir == "":
		return ""
	var f := FileAccess.open(git_dir.path_join("HEAD"), FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text().strip_edges()
	f.close()
	return content

## Status-bar text for raw HEAD content: the branch name, "HEAD@<shortsha>"
## when detached, or "" when empty/unreadable.
static func display_name(head_content: String) -> String:
	var head := head_content.strip_edges()
	if head == "":
		return ""
	if head.begins_with(HEAD_REF_PREFIX):
		return head.substr(HEAD_REF_PREFIX.length()).strip_edges()
	# detached HEAD: HEAD holds the raw commit sha
	return "HEAD@" + head.substr(0, SHORT_SHA_LENGTH)

## What the dock shows: branch name (or detached sha) of project_root,
## "" when it is not a git checkout or HEAD cannot be read.
static func current_branch(project_root: String) -> String:
	return display_name(read_head(resolve_git_dir(project_root)))

# ---------------------------------------------------------------- listing

const HEADS_REF_PREFIX := "refs/heads/"

## All local branch names of project_root, sorted alphabetically. Pure file
## reads like everything else here: loose refs are the files under
## <git_dir>/refs/heads/ (recursively, so "feat/x" counts), packed refs come
## from <git_dir>/packed-refs. Loose refs win over packed ones on name clashes
## (git semantics), which the Dictionary merge below implements naturally.
## Returns empty when project_root is not a git checkout.
static func list_branches(project_root: String) -> PackedStringArray:
	var git_dir := resolve_git_dir(project_root)
	if git_dir == "":
		return PackedStringArray()
	var branches := {}
	_read_packed_refs(git_dir.path_join("packed-refs"), branches)
	_collect_loose_refs(git_dir.path_join("refs/heads"), "", branches)
	var result := branches.keys()
	result.sort()
	return PackedStringArray(result)

## packed-refs lines are "<sha> <refname>"; "^<sha>" lines are peeled tag
## entries and the "#" line is the header — both are skipped.
static func _read_packed_refs(packed_refs_path: String, into: Dictionary) -> void:
	if not FileAccess.file_exists(packed_refs_path):
		return
	var f := FileAccess.open(packed_refs_path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("^"):
			continue
		var space := line.find(" ")
		if space <= 0:
			continue
		var ref := line.substr(space + 1).strip_edges()
		if ref.begins_with(HEADS_REF_PREFIX):
			into[ref.substr(HEADS_REF_PREFIX.length())] = true
	f.close()

## Recursively collect loose refs: every file under dir (subdirs become
## "/"-separated name components) is one ref. Only the relative path matters,
## the file content (the sha) is not needed for a branch listing.
static func _collect_loose_refs(dir: String, prefix: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var rel := prefix + name
			if d.current_is_dir():
				_collect_loose_refs(dir.path_join(name), rel + "/", into)
			else:
				into[rel] = true
		name = d.get_next()
	d.list_dir_end()

# ---------------------------------------------------------------- switching

## `git check-ref-format --branch` essentials: keeps a branch name from being
## misread as a git option ("-...") or containing refname-illegal characters.
static func is_valid_branch_name(name: String) -> bool:
	if name.is_empty() or name.begins_with("-"):
		return false
	if name.begins_with("/") or name.ends_with("/") or name.ends_with(".") \
			or name.ends_with(".lock"):
		return false
	if name.contains("//") or name.contains("..") or name.contains("@{"):
		return false
	for ch in name:
		var o := ch.unicode_at(0)
		if o < 0x20 or o == 0x7F:
			return false
		if " ~^:?*[\\".contains(ch):
			return false
	for part in name.split("/"):
		if part.is_empty() or part.begins_with("."):
			return false
	return true

## Default runner for switch_branch: blocking `git` call with stdout+stderr
## captured. A checkout is normally sub-second; the runner is a parameter so
## tests can substitute a fake and never spawn a process.
static func _default_git_runner(exe: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(exe, args, output, true, true)
	return {"exit_code": exit_code, "output": "\n".join(PackedStringArray(output))}

## Switch project_root to `branch` via `git -C <root> checkout <branch>`.
## `runner` (optional) has the signature func(exe: String, args: PackedStringArray) -> Dictionary
## with "exit_code" and "output" keys; tests inject a fake. Returns a Dictionary
## {"ok": bool, "exit_code": int, "output": String, "branch": String}. checkout
## refuses to clobber uncommitted changes (exit != 0), which surfaces in output.
static func switch_branch(project_root: String, branch: String, runner: Callable = Callable()) -> Dictionary:
	var result := {"ok": false, "exit_code": -1, "output": "", "branch": branch}
	if not is_valid_branch_name(branch):
		result.output = "invalid branch name: %s" % branch
		return result
	if resolve_git_dir(project_root) == "":
		result.output = "not a git checkout: %s" % project_root
		return result
	var args := PackedStringArray(["-C", project_root, "checkout", branch])
	var run := runner if runner.is_valid() else _default_git_runner
	var r: Dictionary = run.call("git", args)
	result.exit_code = int(r.get("exit_code", -1))
	result.output = str(r.get("output", ""))
	result.ok = result.exit_code == 0
	return result
