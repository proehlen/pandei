class_name PipeTransport
extends AcpTransport
## Spawns the vibe-acp executable and talks to it over its stdio pipe.
##
## OS.execute_with_pipe() returns a bidirectional, non-blocking FileAccess on
## the child's stdio (verified on Godot 4.7.2: get_buffer() returns 0 bytes
## immediately when the pipe is empty), so no bridge process is needed.

var _pid := -1
var _stdio: FileAccess = null
var _stderr: FileAccess = null

## Returns OK and sets up the pipes, or an Error code.
func open_executable(exe: String, args: PackedStringArray) -> Error:
	if exe.is_empty() or not FileAccess.file_exists(exe):
		return ERR_FILE_NOT_FOUND
	var proc := OS.execute_with_pipe(exe, args, false)
	_pid = int(proc.get("pid", -1))
	if _pid < 0:
		return ERR_CANT_OPEN
	_stdio = proc.get("stdio")
	_stderr = proc.get("stderr")
	if _stdio == null:
		OS.kill(_pid)
		_pid = -1
		return ERR_CANT_OPEN
	return OK

func open() -> Error:
	# Used when the executable was configured externally; subclasses/tests
	# should call open_executable() instead.
	return ERR_UNAVAILABLE

func read_available() -> PackedByteArray:
	var out := PackedByteArray()
	if _stdio == null:
		return out
	while true:
		var chunk := _stdio.get_buffer(65536)
		if chunk.size() == 0:
			break
		out.append_array(chunk)
	return out

func drain_stderr() -> PackedByteArray:
	var out := PackedByteArray()
	if _stderr == null:
		return out
	while true:
		var chunk := _stderr.get_buffer(65536)
		if chunk.size() == 0:
			break
		out.append_array(chunk)
	return out

func write_bytes(data: PackedByteArray) -> Error:
	if _stdio == null:
		return ERR_UNAVAILABLE
	_stdio.store_buffer(data)
	_stdio.flush()
	return OK

func is_open() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)

func exit_code() -> int:
	if _pid > 0:
		return OS.get_process_exit_code(_pid)
	return -1

func close() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_stdio = null
	_stderr = null
