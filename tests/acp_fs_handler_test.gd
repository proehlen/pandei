extends GdUnitTestSuite

var _tmp_root := ""

func before_test() -> void:
	_tmp_root = "/tmp/acp_fs_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_tmp_root)

func after_test() -> void:
	_remove_recursive(_tmp_root)

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var p := path.path_join(entry)
			if d.current_is_dir():
				_remove_recursive(p)
			else:
				DirAccess.remove_absolute(p)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func test_resolve_path_confines_to_project_root() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	assert_that(fs.resolve_path(_tmp_root + "/src/a.gd")).is_equal(_tmp_root + "/src/a.gd")
	assert_that(fs.resolve_path("src/a.gd")).is_equal(_tmp_root + "/src/a.gd")
	assert_that(fs.resolve_path(_tmp_root)).is_equal(_tmp_root)
	assert_that(fs.resolve_path("/etc/passwd")).is_equal("")
	assert_that(fs.resolve_path(_tmp_root + "/../outside.txt")).is_equal("")
	assert_that(fs.resolve_path("../outside.txt")).is_equal("")
	assert_that(fs.resolve_path("user://save.dat")).is_equal("")

func test_write_then_read_roundtrip() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	var w := fs.handle_write({"path": _tmp_root + "/sub/dir/f.txt", "content": "hello\nworld\n"})
	assert_that(w.has("result")).is_true()
	assert_that(FileAccess.file_exists(_tmp_root + "/sub/dir/f.txt")).is_true()

	var r := fs.handle_read({"path": _tmp_root + "/sub/dir/f.txt"})
	assert_that(r["result"]["content"]).is_equal("hello\nworld\n")

func test_read_honors_line_and_limit() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	fs.handle_write({"path": _tmp_root + "/f.txt", "content": "one\ntwo\nthree\n"})
	var r := fs.handle_read({"path": _tmp_root + "/f.txt", "line": 2, "limit": 1})
	assert_that(r["result"]["content"]).is_equal("two")

func test_read_outside_project_is_refused() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	var r := fs.handle_read({"path": "/etc/passwd"})
	assert_that(r.has("error")).is_true()
	assert_that(int(r["error"]["code"])).is_equal(-32602)

func test_read_missing_file_reports_error() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	var r := fs.handle_read({"path": _tmp_root + "/nope.txt"})
	assert_that(r.has("error")).is_true()

func test_write_outside_project_is_refused() -> void:
	var fs := AcpFsHandler.new(_tmp_root)
	var w := fs.handle_write({"path": "/tmp/acp_fs_escape.txt", "content": "x"})
	assert_that(w.has("error")).is_true()
	assert_that(FileAccess.file_exists("/tmp/acp_fs_escape.txt")).is_false()
