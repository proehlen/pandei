class_name GitBranch
extends RefCounted
## Reads the current git branch of a project for the dock's status bar.
## Pure file reads (no `git` process spawn) so it is cheap enough to poll on
## a timer and trivially testable headless. `.git/HEAD` holds either
## "ref: refs/heads/<branch>" or a raw commit sha (detached HEAD); in linked
## worktrees/submodules `.git` is a file containing "gitdir: <path>".

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
