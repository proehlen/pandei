class_name AcpFsHandler
extends RefCounted
## Handles ACP fs/read_text_file and fs/write_text_file requests.
## All paths are confined to the project root; anything outside is refused.
## Return shape: {"result": Dictionary} or {"error": {"code": int, "message": String}}.

var project_root: String = ""

func _init(p_project_root: String = "") -> void:
	if p_project_root.is_empty():
		project_root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	else:
		project_root = p_project_root.trim_suffix("/")

## Map an incoming path (absolute, res://, or project-relative) to an
## absolute path inside the project. Returns "" when outside the project.
func resolve_path(path: String) -> String:
	var p := path
	if p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	elif p.begins_with("user://") or p.begins_with("~"):
		return ""
	if not p.begins_with("/"):
		p = project_root.path_join(p)
	p = p.simplify_path()
	if p == project_root or p.begins_with(project_root + "/"):
		return p
	return ""

func handle_read(params: Dictionary) -> Dictionary:
	var path := resolve_path(str(params.get("path", "")))
	if path.is_empty():
		return _err(-32602, "Refusing path outside the project: " + str(params.get("path", "")))
	if not FileAccess.file_exists(path):
		return _err(-32002, "File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err(-32002, "Cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
	var content := f.get_as_text()
	f.close()
	var line := int(params.get("line", 1))
	var limit := int(params.get("limit", 2000))
	if line > 1 or limit > 0:
		var lines := content.split("\n")
		var from := clampi(line - 1, 0, lines.size())
		var to := lines.size() if limit <= 0 else mini(from + limit, lines.size())
		content = "\n".join(lines.slice(from, to))
	return {"result": {"content": content}}

func handle_write(params: Dictionary) -> Dictionary:
	var path := resolve_path(str(params.get("path", "")))
	if path.is_empty():
		return _err(-32602, "Refusing path outside the project: " + str(params.get("path", "")))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err(-32002, "Cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
	f.store_string(str(params.get("content", "")))
	f.close()
	return {"result": {}}

static func _err(code: int, message: String) -> Dictionary:
	return {"error": {"code": code, "message": message}}
